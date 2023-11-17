
//
// Check input samplesheet and get read channels
//

include { SAMPLESHEET_CHECK } from '../../modules/local/samplesheet_check'
include { RENAME_READS      } from '../../modules/local/rename_reads'

workflow INPUT_CHECK {
    take:
    samplesheet // file: /path/to/samplesheet.csv

    main:
    ch_parsed_reads =
        SAMPLESHEET_CHECK ( samplesheet ).csv
        .splitCsv ( header:true, sep:',' )
        .map { create_fastq_channel(it) }

    if (params.aligner == 'cellrangermulti') {
        ch_renamed_reads = RENAME_READS ( ch_parsed_reads ).reads
    } else {
        ch_renamed_reads = ch_parsed_reads
    }

    ch_renamed_reads
        .groupTuple(by: [0]) // group replicate files together, modifies channel to [ val(meta), [ [reads_rep1], [reads_repN] ] ]
        .map { meta, reads -> [ meta, reads.flatten() ] } // needs to flatten due to last "groupTuple", so we now have reads as a single array as expected by nf-core modules: [ val(meta), [ reads ] ]
        .set { reads }

    emit:
    reads                                     // channel: [ val(meta), [ reads ] ]
    versions = SAMPLESHEET_CHECK.out.versions // channel: [ versions.yml ]
}


// Function to get list of [ meta, [ fastq_1, fastq_2 ] ]
def create_fastq_channel(LinkedHashMap row) {
    // create meta map
    def meta = [:]
    meta.id             = row.sample
    meta.single_end     = row.single_end.toBoolean()
    meta.expected_cells = row.expected_cells ?: null
    meta.seq_center     = row.seq_center ?: params.seq_center

    // check for cellranger multi
    if (params.aligner == 'cellrangermulti') {
        assert row.feature_type, "Error. Running ${params.aligner} aligner but forgot to add feature_type column. See sample ${row.sample}"
        if (row.feature_type == 'cmo') assert params.cmo_barcode_csv, "Error. Input is feature_type==cmo, but cmo_barcodes was not given. See sample ${row.sample}"
        meta.feature_type   = row.feature_type
    }

    // add path(s) of the fastq file(s) to the meta map
    def fastq_meta = []
    if (!file(row.fastq_1).exists()) {
        exit 1, "ERROR: Please check input samplesheet -> Read 1 FastQ file does not exist!\n${row.fastq_1}"
    }
    if (meta.single_end) {
        fastq_meta = [ meta, [ file(row.fastq_1) ] ]
    } else {
        if (!file(row.fastq_2).exists()) {
            exit 1, "ERROR: Please check input samplesheet -> Read 2 FastQ file does not exist!\n${row.fastq_2}"
        }
        fastq_meta = [ meta, [ file(row.fastq_1), file(row.fastq_2) ] ]
    }
    return fastq_meta
}
