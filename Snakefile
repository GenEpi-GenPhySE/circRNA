# snakemake -p cow-liver-B004/R1.Chimeric.out.junction cow-liver-B004/R2.Chimeric.out.junction --until all

# imports:
import sys
import re
import yaml
import os.path
import pandas as pd
from snakemake.utils import report


def message(mes):
    sys.stderr.write("|--- " + mes + "\n")


def get_samples(sample_file):
    samples = pd.read_table(config["samples"],
                            dtype={"sample": str}).set_index("sample", drop=False)
    return samples


def get_annotation(wildcards):
    species = get_species(wildcards.sample, samples)
    if species not in config['annotations']:
        print(wildcards.sample)
        print(species)
        print(config['annotations'])
        print("Warning the species %s is absent from aconfig file" % species)
        exit(1)
    return config['annotations'][species]


def get_star_outdir(sample, samples):
    starse_outdir = samples.loc[sample, "mapdir"]
    return starse_outdir


def get_species(sample, samples):
    species = samples.loc[sample, "species"]
    return species


def get_se_chimeric_junctions(wildcards):
    starse_outdir = get_star_outdir(wildcards.sample, samples)
    R1 = os.path.join(starse_outdir, "R1", "Chimeric.out.junction")
    R2 = os.path.join(starse_outdir, "R2", "Chimeric.out.junction")
    return {"R1": R1, "R2": R2}


def get_log_file(wildcards):
    logfile_outdir = get_star_outdir(wildcards.sample, samples)
    sample = wildcards.sample
    log_R1 = os.path.join(logfile_outdir, "R1", "Log.final.out")
    log_R2 = os.path.join(logfile_outdir, "R2", "Log.final.out")
    return {"sample": sample, "log_R1": log_R1, "log_R2": log_R2}


configfile: "config.yaml"
workdir: config["wdir"]
message("The current working directory is " + config['wdir'])

samples = get_samples(config['samples'])

# Wildcard constraints
wildcard_constraints:
    sample = "|".join(samples.index)


rule all:
    input:
        expand("{sample}/{sample}_detection.bed", sample=samples.index),
        expand("{sample}/{sample}_annotation.out", sample=samples.index),
        expand("{sample}/{sample}_stats_annotation.tsv", sample=samples.index),
        expand("{sample}/{sample}_intronic_circRNAs.tsv", sample=samples.index),
        expand("{sample}/{sample}_exonic_circRNAs.tsv", sample=samples.index),
        expand("{sample}/{sample}_exonic_summary.tsv", sample=samples.index),
        expand("{sample}/{sample}_subexonic_pleg_circRNAs.tsv", sample=samples.index),
        expand("{sample}/{sample}_subexonic_meg_circRNAs.tsv", sample=samples.index),
        expand("{sample}/{sample}_meg_summary.tsv", sample=samples.index),
        expand("{sample}/{sample}_intronic_summary.tsv", sample=samples.index),
        expand("{sample}/{sample}_pleg_summary.tsv", sample=samples.index),
        "stats_annotation_all.tsv",
        #"exonic_comparison_all.tsv",
        #"logs/merged_bed.log",
        "mapping_stat.tsv"
    shell:
        "find {input} -type f -empty -delete"


rule mergeexoniccomparison:
    input:
        expand("{sample}/{sample}_exonic_summary.tsv", sample=samples.index)
    output:
        "exonic_comparison_all.tsv"
    shell:
        "cat {{bta,oar,ssc}}_*/*_exonic_summary.tsv | cut -f1,3,4 |tail -n+2|sort|uniq > {output}"


rule summaryannotation:
    input:
        meg = "{sample}/{sample}_subexonic_meg_circRNAs.tsv",
        pleg = "{sample}/{sample}_subexonic_pleg_circRNAs.tsv",
        intronic = "{sample}/{sample}_intronic_circRNAs.tsv"
    output:
        meg = "{sample}/{sample}_meg_summary.tsv",
        pleg = "{sample}/{sample}_pleg_summary.tsv",
        intronic = "{sample}/{sample}_intronic_summary.tsv"
    log:
        stdout = "logs/{sample}_summary_annotation.o",
        stderr = "logs/{sample}_summary_annotation.e"
    params:
        min_size = config["min_size"]
    shell:
        "python3 ../scripts/summary_table.py -ip {input.pleg} -im {input.meg} -ii {input.intronic}"
        " -op {output.pleg} -om {output.meg} -oi {output.intronic} -ms {params.min_size}"
        " 1>{log.stdout} 2>{log.stderr}"


rule mergestatannotation:
    input:
        expand("{sample}/{sample}_stats_annotation.tsv", sample=samples.index)
    output:
        "stats_annotation_all.tsv"
    shell:
        "cat {input} >> {output}"


rule statannotation:
    input:
        "{sample}/{sample}_annotation.out"
    output:
        stats = "{sample}/{sample}_stats_annotation.tsv",
        intronic = "{sample}/{sample}_intronic_circRNAs.tsv",
        exonic = "{sample}/{sample}_exonic_circRNAs.tsv",
        comp_exonic = "{sample}/{sample}_exonic_summary.tsv",
        sub_exonic_pleg = "{sample}/{sample}_subexonic_pleg_circRNAs.tsv",
        sub_exonic_meg = "{sample}/{sample}_subexonic_meg_circRNAs.tsv"
    log:
        stdout = "logs/{sample}_stat_annotation.o",
        stderr = "logs/{sample}_stat_annotation.e"
    params:
        min_ccr = config["min_ccr"]
    shell:
        "python3 ../scripts/stats_annotation.py -i {input} -o_stats {output.stats} -min_cr {params.min_ccr}"
        " -oi {output.intronic} -oe {output.exonic} -oce {output.comp_exonic} -osepleg {output.sub_exonic_pleg}"
        " -osemeg {output.sub_exonic_meg}"
        " 1>{log.stdout} 2>{log.stderr}"


rule annotation:
    input:
        circ_detected = "{sample}/{sample}_detection.bed",
        annot_exon = get_annotation
    output:
        "{sample}/{sample}_annotation.out"
    log:
        stdout = "logs/{sample}_annotation.o",
        stderr = "logs/{sample}_annotation.e"
    shell:
        "python3 ../scripts/circRNA_annotation.py -circ {input.circ_detected}"
        " -annot {input.annot_exon} -fmt bed -o {output} 1>{log.stdout} 2>{log.stderr}"


rule cumul_bed:
    input:
        config["samples"]
    log:
        "logs/merged_bed.log"
    shell:
        "python3 ../scripts/cumul_bed.py -sp {input} > {log}"

rule detection:
    input:
        unpack(get_se_chimeric_junctions)
    output:
        "{sample}/{sample}_detection.bed"
    log:
        stdout = "logs/{sample}_detection.o",
        stderr = "logs/{sample}_detection.e"
    params:
        min_ccr = config["min_ccr"],
        tolerance = config["tolerance"]
    shell:
        "if grep -q 'Nreads' {input.R1}; then head -n -2 {input.R1} > {input.R1}2; mv {input.R1}2 {input.R1}; fi ;"
        " if grep -q 'Nreads' {input.R2}; then head -n -2 {input.R2} > {input.R2}2; mv {input.R2}2 {input.R2}; fi ;"
        " python3 ../scripts/circRNA_detection.py -r1 {input.R1} -r2 {input.R2}"
        " -min_cr {params.min_ccr} -tol {params.tolerance} -fmt bed -o {output} 1>{log.stdout} 2>{log.stderr}"

rule mergemappingstat:
    input:
        config["samples"]
    output:
        "mapping_stat.tsv"
    shell:
        "python3 ../scripts/stats_mapping.py -i {input} -o {output}"
