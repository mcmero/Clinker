#!/bin/bash
#------------------------------------------------------------------------------------------
# Get variables
#------------------------------------------------------------------------------------------
fusion=$1
fusion_folder=$2
fusion_friendly=$3
results_folder=$4
fastq_1=$5
fastq_2=$6
annotation_folder=$results_folder'/annotation'
alignment_folder=$results_folder'/alignment'
alignment_folder_close=$results_folder'/alignment/'
aligned=$alignment_folder'/Aligned.sortedByCoord.out.bam'
reference_folder=$results_folder'/reference'
genome_folder=$results_folder'/genome'
fst=$reference_folder'/fst_reference.fasta'
#------------------------------------------------------------------------------------------
# Generate Genome & Align
#------------------------------------------------------------------------------------------
STAR --runMode genomeGenerate --runThreadN 1 --genomeDir $genome_folder --genomeFastaFiles $fst --genomeSAindexNbases 5
STAR --genomeDir $genome_folder --readFilesIn $fastq_1 $fastq_2 --readFilesCommand zcat --outSAMtype BAM SortedByCoordinate --runThreadN 1 --outFileNamePrefix $alignment_folder_close --limitBAMsortRAM 1004462444
#------------------------------------------------------------------------------------------
# Generate Genome & Align
#------------------------------------------------------------------------------------------
samtools index $aligned
bamCoverage -b $aligned --normalizeUsingRPKM -of bedgraph --binSize 1 -o $alignment_folder/coverage_rpm.bedgraph
#------------------------------------------------------------------------------------------
# Make a fusion folder directory
#------------------------------------------------------------------------------------------
if [ ! -d $fusion_folder ];
	then mkdir $fusion_folder;
fi
#------------------------------------------------------------------------------------------
# Reduce BAM file to include only reads from desired fusion, this will reduce space
#------------------------------------------------------------------------------------------
printf '\n'
echo $fusion
echo '------------------------------------------'
echo 'filtering BAM file for fusion of interest'
samtools view -hq 1 $alignment_folder/Aligned.sortedByCoord.out.bam $fusion | \
			samtools view -Sb - > $fusion_folder/${fusion_friendly}.bam
samtools index $fusion_folder/${fusion_friendly}.bam
#------------------------------------------------------------------------------------------
# Filter out reads with overhangs less than 15 (accounts for much of the noise in final plot)
#------------------------------------------------------------------------------------------
echo 'filtering BAM file for reads with overhangs < 15 (noise reduction)'
samtools view -h $fusion_folder/${fusion_friendly}.bam | \
awk '{if($0 ~ /^@/){print $0;} else {cigar = $6; gsub("([0-9]+[S])","",cigar); gsub("([0-9]+[I])","",cigar); gsub("([0-9]+[D])","",cigar); gsub("([0-9]+[N])"S,"",cigar); m = split(cigar,matches,"M"); if(m > 2) {if(matches[1] > 15 && matches[m-1] > 15){print $0;}} else if(m <= 2) {print $0;}}}' | \
samtools view -Sb - > $fusion_folder/${fusion_friendly}_lt15.bam
#------------------------------------------------------------------------------------------
# Create files including only reads involved in fusion and only the other reads
#------------------------------------------------------------------------------------------
echo 'Creating ancillilary files'
grep $fusion $annotation_folder/gene_boundaries.bed | awk '$5 == 1' | sort | head -n 1 | awk -v fusion="$fusion" '{print fusion"\t"$2"\t"$2+1}' > $fusion_folder/fusion_locations.bed
samtools view $fusion_folder/${fusion_friendly}_lt15.bam -b -h -o $fusion_folder/fusion_reads.bam -U $fusion_folder/reads.bam -L $fusion_folder/fusion_locations.bed
samtools view -h $fusion_folder/fusion_reads.bam | awk '{if($0 ~ /^@/ || $6 ~ /N/) {print $0}}' | samtools view -Sb - > $fusion_folder/split_reads.bam
#------------------------------------------------------------------------------------------
# Index the new bam files
#------------------------------------------------------------------------------------------
echo 'Index BAM files'
samtools index $fusion_folder/reads.bam
samtools index $fusion_folder/fusion_reads.bam
samtools index $fusion_folder/split_reads.bam
#------------------------------------------------------------------------------------------
# Create SJ.Tab.out
#------------------------------------------------------------------------------------------
samtools view -h -o $fusion_folder/${fusion_friendly}.sam $fusion_folder/${fusion_friendly}_lt15.bam
awk -f /mnt/storage/guest/breon/final/plotit/sj_out_gen.awk $fusion_folder/${fusion_friendly}.sam | sort -V > $fusion_folder/junctions.txt