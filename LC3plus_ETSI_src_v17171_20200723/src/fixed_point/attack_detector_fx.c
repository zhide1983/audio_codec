/******************************************************************************
*                        ETSI TS 103 634 V1.2.1                               *
*              Low Complexity Communication Codec Plus (LC3plus)              *
*                                                                             *
* Copyright licence is solely granted through ETSI Intellectual Property      *
* Rights Policy, 3rd April 2019. No patent licence is granted by implication, *
* estoppel or otherwise.                                                      *
******************************************************************************/
                                                                               

#include "functions.h"

void attack_detector_fx(LC3_Enc *enc, EncSetup *setup, Word16 *input, Word16 input_scaling, void *scratch)
{
    Dyn_Mem_Deluxe_In(
        int    i, j, position;
        Word32 tmp, *block_energy;
        Word16 h16, l16, new_scaling, rescale, input_delta_scaling;
        Word16 scales[3], *input_16k;
        Word16 frame_length_16k;
    );

    block_energy = scratchAlign(scratch, 0);
    input_16k    = scratchAlign(block_energy, 4 * 4 + 4);
    frame_length_16k = i_mult(enc->attdec_nblocks, 40);

    IF (setup->attack_handling)
    {
        /* input scaling */
        scales[0] = add(getScaleFactor16(input, enc->frame_length), input_scaling);
        scales[1] = add(getScaleFactor16_0(setup->attdec_filter_mem, 2), setup->attdec_scaling);
        scales[2] =
            shr(add(add(getScaleFactor32_0(&setup->attdec_acc_energy, 1), shl(setup->attdec_scaling, 1)), 1), 1);
        new_scaling = s_min(scales[0], s_min(scales[1], scales[2]));

        new_scaling = sub(new_scaling, 2); /* add overhead for resampler*/

        /* memory re-scaling */
        rescale = sub(new_scaling, setup->attdec_scaling);

        IF (rescale)
        {
            setup->attdec_filter_mem[0] = shl(setup->attdec_filter_mem[0], rescale);        move16();
            setup->attdec_filter_mem[1] = shl(setup->attdec_filter_mem[1], rescale);        move16();
            setup->attdec_acc_energy    = L_shl(setup->attdec_acc_energy, shl(rescale, 1)); move16();
        }
        setup->attdec_scaling = new_scaling; move16();

        SWITCH (enc->fs)
        {
        case 32000:
            input_delta_scaling = sub(1, sub(new_scaling, input_scaling));
            FOR (i = 0; i < frame_length_16k; i++)
            {
                input_16k[i] = add(shr(input[2 * i + 0], input_delta_scaling),
                                   shr(input[2 * i + 1], input_delta_scaling)); move16();
            }
            break;
        case 48000:
            input_delta_scaling = sub(2, sub(new_scaling, input_scaling));
            FOR (i = 0; i < frame_length_16k; i++)
            {
                input_16k[i] = add(shr(input[3 * i + 0], input_delta_scaling),
                                   add(shr(input[3 * i + 1], input_delta_scaling),
                                       shr(input[3 * i + 2], input_delta_scaling))); move16();
            }
            break;
        default: ASSERT(!"sampling rate not supported in function attack_detector_fx!"); break;
        }

        input_16k[-2]               = setup->attdec_filter_mem[0]; move16();
        input_16k[-1]               = setup->attdec_filter_mem[1]; move16();
        setup->attdec_filter_mem[0] = input_16k[frame_length_16k - 2];              move16();
        setup->attdec_filter_mem[1] = input_16k[frame_length_16k - 1];              move16();

        FOR (i = frame_length_16k - 1; i >= 0; i--)
        {
            tmp = L_mult(input_16k[i], 12288);
            tmp = L_msu(tmp, input_16k[i - 1], 16384);
            tmp = L_mac(tmp, input_16k[i - 2], 4096);

            input_16k[i] = extract_h(tmp); move16();
        }

        basop_memset(block_energy, 0, 4 * sizeof(Word32));

        FOR (j = 0; j < enc->attdec_nblocks; j++)
        {
			FOR (i = 0; i < 40; i++)
			{
				block_energy[j] = L_mac(block_energy[j], input_16k[i + j*40], input_16k[i + j*40]);     move16();
			}
        }

        setup->attdec_detected = setup->attdec_position >= enc->attdec_hangover_thresh;
        test();        move16();
        position = -1; move16();

        FOR (i = 0; i < enc->attdec_nblocks; i++)
        {
            /* block_energy[i] / 8.5 */
            l16 = extract_l(L_shr(block_energy[i], 1));
            l16 = s_and(l16, 0x7fff);
            h16 = extract_h(block_energy[i]);
            tmp = L_shr(L_mult0(l16, 30840), 15);
            tmp = L_shr(L_mac0(tmp, h16, 30840), 2);

            IF (tmp > setup->attdec_acc_energy)
            {
                position               = i; move16();
                setup->attdec_detected = 1; move16();
            }
            setup->attdec_acc_energy = L_max(L_shr(setup->attdec_acc_energy, 2), block_energy[i]); move16();
        }
        setup->attdec_position = position; move16();
    }

    Dyn_Mem_Deluxe_Out();
}
