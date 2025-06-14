/******************************************************************************
*                        ETSI TS 103 634 V1.2.1                               *
*              Low Complexity Communication Codec Plus (LC3plus)              *
*                                                                             *
* Copyright licence is solely granted through ETSI Intellectual Property      *
* Rights Policy, 3rd April 2019. No patent licence is granted by implication, *
* estoppel or otherwise.                                                      *
******************************************************************************/
                                                                               

#include "setup_dec_lc3.h"
#include "functions.h"
#include <stdio.h>
#include <assert.h>

/* if decoder is null only size is reported */
int alloc_decoder(LC3_Dec* decoder, int channels)
{
    int    ch   = 0;
    size_t size = sizeof(LC3_Dec);

    for (ch = 0; ch < channels; ch++) {
        DecSetup* setup = balloc(decoder, &size, sizeof(DecSetup));

        if (decoder) {
            decoder->channel_setup[ch] = setup;
        }
    }

    return (int)size;
}

LC3_Error FillDecSetup(LC3_Dec* decoder, int samplerate, int channels, LC3_PlcMode plc_mode)
{
    memset(decoder, 0, lc3_dec_get_size(samplerate, channels));
    alloc_decoder(decoder, channels);

    decoder->fs     = CODEC_FS(samplerate);
    decoder->fs_out = samplerate;
    decoder->fs_idx = FS2FS_IDX(decoder->fs);
    decoder->plcMeth = plc_mode;
    
    
    if (decoder->fs_idx > 4) {
        decoder->fs_idx = 5;
    }
    decoder->channels       = channels;
    decoder->frame_ms       = 10;
    decoder->frame_dms      = 100;
    decoder->BW_cutoff_bits = BW_cutoff_bits_all[decoder->fs_idx];
    
    if (decoder->fs == 8000) {
        decoder->tilt = 14;
    } else if (decoder->fs == 16000) {
        decoder->tilt = 18;
    } else if (decoder->fs == 24000) {
        decoder->tilt = 22;
    } else if (decoder->fs == 32000) {
        decoder->tilt = 26;
    } else if (decoder->fs == 48000) {
        decoder->tilt = 30;
    }
    else if (decoder->fs == 96000) {
        decoder->tilt = 34;
    }

    set_dec_frame_params(decoder);

    
    return LC3_OK;
}

/* set frame config params */
void set_dec_frame_params(LC3_Dec* decoder)
{
    int ch = 0;
    
    if (decoder->fs_idx == 5)
    {
        decoder->hrmode = 1;
    }

    decoder->frame_length = ceil(decoder->fs * 10 / 1000); /* fs * 0.01*2^6 */
    if (decoder->hrmode == 1)
    {
        decoder->yLen = decoder->frame_length;
    }
    else
    {
        decoder->yLen = MIN(MAX_BW, decoder->frame_length);
    }

    decoder->bands_number = 64;
    if (decoder->frame_ms == 2.5) 
    {
        decoder->frame_length = decoder->frame_length >> 2;
        decoder->yLen /= 4;
        if (decoder->hrmode)
        {
            decoder->bands_number = bands_number_2_5ms_HR[decoder->fs_idx];
        } 
        else
        {
            decoder->bands_number = bands_number_2_5ms[decoder->fs_idx];
        }
    }
    if (decoder->frame_ms == 5) 
    {
        decoder->frame_length = decoder->frame_length >> 1;
        decoder->yLen /= 2;
        decoder->bands_number = bands_number_5ms[decoder->fs_idx];
    }

    if (decoder->hrmode)
    {
        decoder->BW_cutoff_bits    = 0;
    }
    else
    {
        decoder->BW_cutoff_bits    = BW_cutoff_bits_all[decoder->fs_idx];
    }

    if (decoder->frame_ms == 10) 
    {
        if (decoder->hrmode)
        {
            decoder->bands_offset = ACC_COEFF_PER_BAND_HR[decoder->fs_idx];
        }
        else
        {
            decoder->bands_offset = ACC_COEFF_PER_BAND[decoder->fs_idx];
        }
        decoder->cutoffBins   = BW_cutoff_bin_all;
    }
    else if (decoder->frame_ms == 2.5) 
    {
        if (decoder->hrmode)
        {
            decoder->bands_offset = ACC_COEFF_PER_BAND_2_5ms_HR[decoder->fs_idx];
        }
        else
        {
            decoder->bands_offset = ACC_COEFF_PER_BAND_2_5ms[decoder->fs_idx];
        }
        decoder->cutoffBins   = BW_cutoff_bin_all_2_5ms;
    }
    else if (decoder->frame_ms == 5) 
    {
        if (decoder->hrmode)
        {
            decoder->bands_offset = ACC_COEFF_PER_BAND_5ms_HR[decoder->fs_idx];
        }
        else
        {
            decoder->bands_offset = ACC_COEFF_PER_BAND_5ms[decoder->fs_idx];
        }
        decoder->cutoffBins   = BW_cutoff_bin_all_5ms;
    }
    
    
    if (decoder->frame_ms == 10) {
        decoder->imdct_win     = MDCT_WINS_10ms[decoder->hrmode][decoder->fs_idx];
        decoder->imdct_laZeros = MDCT_la_zeroes[decoder->fs_idx];
        decoder->imdct_winLen  = MDCT_WINDOWS_LENGTHS_10ms[decoder->fs_idx];
    }
    else if (decoder->frame_ms == 2.5) {
        decoder->imdct_win     = MDCT_WINS_2_5ms[decoder->hrmode][decoder->fs_idx];
        decoder->imdct_laZeros = MDCT_la_zeroes_2_5ms[decoder->fs_idx];
        decoder->imdct_winLen  = MDCT_WINDOWS_LENGTHS_2_5ms[decoder->fs_idx];
    }
    else if (decoder->frame_ms == 5) {
        decoder->imdct_win     = MDCT_WINS_5ms[decoder->hrmode][decoder->fs_idx];
        decoder->imdct_laZeros = MDCT_la_zeroes_5ms[decoder->fs_idx];
        decoder->imdct_winLen  = MDCT_WINDOWS_LENGTHS_5ms[decoder->fs_idx];
    }

    decoder->la_zeroes = decoder->imdct_laZeros;

    decoder->imdct_memLen = decoder->frame_length - decoder->imdct_laZeros;

    for (ch = 0; ch < decoder->channels; ch++) {
        DecSetup* setup = decoder->channel_setup[ch];
        
        setup->ltpf_mem_beta_idx = -1;
        

        if (decoder) {
            /* Init DCT4 structs */
            if (setup->dct4structImdct.length != 0) {
                dct4_free(&setup->dct4structImdct);
                dct4_init(&setup->dct4structImdct, decoder->frame_length);
            } else {
                dct4_init(&setup->dct4structImdct, decoder->frame_length);
            }
            
            setup->PlcNsSetup.cum_alpha = 1;
            setup->PlcNsSetup.seed = 24607;
            setup->alpha = 1;
        }
    }
}

LC3_Error update_dec_bitrate(LC3_Dec* decoder, int ch, int nBytes)
{
    int totalBits = 0, bitsTmp = 0, channel_bytes = 0, maxBytes = 0, minBytes = 0;

    if (decoder->hrmode)
    {
        switch (decoder->frame_dms)
        {
        case 25:
            maxBytes = 210;
            if (decoder->fs == 48000) {minBytes = 54;}
            else if (decoder->fs == 96000) {minBytes = 62;}
            else { return LC3_HRMODE_ERROR;}
            break;
        case 50:
            maxBytes = 375;
            if (decoder->fs == 48000) {minBytes = 93;}
            else if (decoder->fs == 96000) {minBytes = 109;}
            else { return LC3_HRMODE_ERROR;}
            break;
        case 100:
            maxBytes = 625;
            if (decoder->fs == 48000) {minBytes = 156;}
            else if (decoder->fs == 96000) {minBytes = 187;}
            else { return LC3_HRMODE_ERROR;}
            break;
        default:
            return LC3_HRMODE_ERROR;
        }
    }
    else
    {
        minBytes = MIN_NBYTES;
        maxBytes = MAX_NBYTES;
    }

    channel_bytes = nBytes;

        DecSetup* setup = decoder->channel_setup[ch];

        if (channel_bytes < minBytes || channel_bytes > maxBytes)
        {
            return LC3_NUMBYTES_ERROR;
        }
    
        setup->targetBytes          = channel_bytes;
        setup->total_bits           = setup->targetBytes << 3;
        setup->enable_lpc_weighting = (setup->total_bits < 480);
        setup->quantizedGainOff =
            -(MIN(115, setup->total_bits / (10 * (decoder->fs_idx + 1))) + 105 + 5 * (decoder->fs_idx + 1));

        totalBits = setup->total_bits;
        
        if (decoder->frame_ms == 2.5) {
            setup->enable_lpc_weighting = setup->total_bits < 120;
            totalBits                   = setup->total_bits * 4.0 * (1.0 - 0.4);
        }
        if (decoder->frame_ms == 5) {
            setup->enable_lpc_weighting = (setup->total_bits < 240);
            totalBits                   = setup->total_bits * 2 - 160;
        }
    
        if (decoder->frame_length > 40 * ((LC3_FLOAT) (decoder->frame_dms) / 10.0)) {
            setup->N_red_tns  = 40 * ((LC3_FLOAT) (decoder->frame_dms) / 10.0);
            setup->fs_red_tns = 40000;
        } else {
            setup->N_red_tns = decoder->frame_length;
            setup->fs_red_tns = decoder->fs;
        }

        bitsTmp = totalBits;
        
        if (bitsTmp < 400 + (decoder->fs_idx - 1) * 80) {
            setup->ltpf_conf_beta     = 0.4;
            setup->ltpf_conf_beta_idx = 0;
        } else if (bitsTmp < 480 + (decoder->fs_idx - 1) * 80) {
            setup->ltpf_conf_beta     = 0.35;
            setup->ltpf_conf_beta_idx = 1;
        } else if (bitsTmp < 560 + (decoder->fs_idx - 1) * 80) {
            setup->ltpf_conf_beta     = 0.3;
            setup->ltpf_conf_beta_idx = 2;
        } else if (bitsTmp < 640 + (decoder->fs_idx - 1) * 80) {
            setup->ltpf_conf_beta     = 0.25;
            setup->ltpf_conf_beta_idx = 3;
        } else {
            setup->ltpf_conf_beta     = 0;
            setup->ltpf_conf_beta_idx = -1;
        }

        /* No LTPF in hrmode */
        if (decoder->hrmode == 1) {
            setup->ltpf_conf_beta     = 0;
            setup->ltpf_conf_beta_idx = -1;
        }
    
    return LC3_OK;
}
