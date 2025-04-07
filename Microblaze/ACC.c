#include "xil_cache.h"
#include "xemaclite.h"
#include "xparameters.h"
#include "xil_printf.h"
#include "xtmrctr.h"
#include "platform.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include "xuartlite.h"


//Add UARTLite globals
#define UARTLITE_DEVICE_ID XPAR_UARTLITE_0_DEVICE_ID
XUartLite UartLite;

// Definitions for Reception and Inference
#define MAX_PKT_LEN              1518    // Maximum Ethernet frame size (including padding)
#define DRAM_BASE_ADDR           0x84030000  // DRAM base where tensor binary file is stored
#define TOTAL_TENSORS            18     // Total number of tensors expected in the binary file
#define ACK_ETHER_TYPE           0x88B7  // EtherType for ACK/NACK packets
#define REQUEST_ETHER_TYPE       0x88B6  // EtherType for FPGA-to-PC request
#define BUTTONS_BASE_ADDR        0x40000000  // Base address for buttons GPIO
#define RAND_OUTPUT_BASE_ADDR    0x86000000
#define DELAY_COUNT              0   // delay to give accelerator time to produce output

// Custom fragment header sizes.
#define ETH_HEADER_SIZE              14
#define FRAGMENT_HEADER_SIZE_FIRST   20
#define FRAGMENT_HEADER_SIZE         16


// Inference parameters for the first convolution layer.
#define INPUT_HEIGHT 124
#define INPUT_WIDTH 129
#define INPUT_CHANNELS 1
#define CONV1_FILTERS 32
#define CONV1_KERNEL_HEIGHT 3    // 3x3 kernel
#define CONV1_KERNEL_WIDTH 3
#define CONV1_OUTPUT_HEIGHT (INPUT_HEIGHT - CONV1_KERNEL_HEIGHT + 1)  // 122
#define CONV1_OUTPUT_WIDTH  (INPUT_WIDTH - CONV1_KERNEL_WIDTH + 1)     // 127

// Inference parameters for the second convolution layer (conv2).
#define CONV2_INPUT_HEIGHT CONV1_OUTPUT_HEIGHT    // 122
#define CONV2_INPUT_WIDTH  CONV1_OUTPUT_WIDTH       // 127
#define CONV2_INPUT_CHANNELS 32                     // Conv1 output channels
#define CONV2_FILTERS 64
#define CONV2_KERNEL_HEIGHT 3
#define CONV2_KERNEL_WIDTH 3
#define CONV2_OUTPUT_HEIGHT (CONV2_INPUT_HEIGHT - CONV2_KERNEL_HEIGHT + 1)  // 120
#define CONV2_OUTPUT_WIDTH  (CONV2_INPUT_WIDTH - CONV2_KERNEL_WIDTH + 1)     // 125

// Fully Connected layer
#define FC1_OUTPUT_SIZE       128  // Number of neurons in FC1
#define FC2_OUTPUT_SIZE       8    // 8 output classes

// Accelerator Memory Map Definitions
#define ACC_BASE_ADDR    0xC0000000  // Base address of accelerator IP
#define ACC_FILTER_BASE   (ACC_BASE_ADDR)           // buffer 0 filter/input registers.
#define ACC_INPUT_BASE    0xC000000C   // buffer 0 input registers.
#define ACC_OUTPUT_ADDR   0x87E00000   // Accelerator outputs



// Seven Segment Display Map Definition & Variable
#define SEVEN_SEG_ADDR   0x20000000
volatile uint32_t* seg_ptr = (volatile uint32_t*) SEVEN_SEG_ADDR;

// Global variable to track continuous accelerator output offset (in bytes).
uint32_t acc_output_offset = 0;

// Global Variables
XEmacLite EmacLiteInstance;
u8 RecvBuffer[MAX_PKT_LEN];

// Audio
#define AUDIO_TENSOR_ID 99
#define AUDIO_BUFFER_SIZE (124 * 129)
u8 AudioInputBuffer[AUDIO_BUFFER_SIZE];
unsigned int audio_offset = 0;
int audio_ready = 0;

u8 FPGA_MAC[6] = {0x02,0xAA,0xBB,0xCC,0xDD,0xEE};
u8 PC_MAC[6]   = {0x9C,0xEB,0xE8,0xAE,0x7E,0xF5};

volatile unsigned int *button = (volatile unsigned int*)BUTTONS_BASE_ADDR;

// DRAM pointer for received tensor binary data
volatile u8 *DRAM_ptr = (volatile u8 *)DRAM_BASE_ADDR;
unsigned int current_offset = 0;  // Next free offset in DRAM

// Global arrays for tensor offsets and sizes
unsigned int tensor_offsets[TOTAL_TENSORS];
unsigned int tensor_sizes[TOTAL_TENSORS];
unsigned int tensor_count = 0;

// To track the expected fragment index
unsigned int expected_fragment_index = 0;


u32 get_u32(u8 *data) {
    return ((u32)data[0]) |
           ((u32)data[1] << 8) |
           ((u32)data[2] << 16) |
           ((u32)data[3] << 24);
}

typedef struct {
    u32 tensor_id;
    u32 fragment_index;
    u8 status;  // 1 for ACK, 0 for NACK
    u8 reserved[3];
} AckPacket;

void send_ack(u32 tensor_id, u32 fragment_index, u8 status) {
    u8 ack_packet[14 + sizeof(AckPacket)];
    // Set Ethernet header: Destination = PC_MAC, Source = FPGA_MAC, EtherType = ACK_ETHER_TYPE.
    memcpy(ack_packet, PC_MAC, 6);
    memcpy(ack_packet + 6, FPGA_MAC, 6);
    ack_packet[12] = (ACK_ETHER_TYPE >> 8) & 0xFF;
    ack_packet[13] = ACK_ETHER_TYPE & 0xFF;

    AckPacket ack;
    ack.tensor_id = tensor_id;
    ack.fragment_index = fragment_index;
    ack.status = status;
    memset(ack.reserved, 0, sizeof(ack.reserved));

    memcpy(ack_packet + 14, &ack, sizeof(AckPacket));

    XEmacLite_Send(&EmacLiteInstance, ack_packet, 14 + sizeof(AckPacket));
    xil_printf("Sent %s for tensor %d fragment %d\n", (status==1 ? "ACK" : "NACK"), tensor_id, fragment_index);
}

void process_packet(u8 *packet, int length) {
    if (length < ETH_HEADER_SIZE) return;
    if (packet[12] != 0x88 || packet[13] != 0xB5) return;

    u8 *header_ptr = packet + ETH_HEADER_SIZE;
    int header_size = 0;
    u32 tensor_id, fragment_index, total_fragments, tensor_size = 0;
    u32 actual_payload_length = 0;

    if (length < ETH_HEADER_SIZE + FRAGMENT_HEADER_SIZE)
    {
        xil_printf("Packet too short, length %d\n", length);
        return;
    }

    tensor_id = get_u32(header_ptr);
    fragment_index = get_u32(header_ptr + 4);
    total_fragments = get_u32(header_ptr + 8);

    xil_printf("Received fragment index %d (expected %d) for tensor %d, packet length %d\n",
               fragment_index, expected_fragment_index, tensor_id, length);

    if (fragment_index == 0) {
        if (length < ETH_HEADER_SIZE + FRAGMENT_HEADER_SIZE_FIRST) {
            xil_printf("First fragment packet too short, length %d\n", length);
            return;
        }
        tensor_size = get_u32(header_ptr + 12);
        actual_payload_length = get_u32(header_ptr + 16);
        header_size = FRAGMENT_HEADER_SIZE_FIRST;
        xil_printf("Received first fragment for tensor %d, total fragments %d, tensor size %d, actual payload %d\n",
                   tensor_id, total_fragments, tensor_size, actual_payload_length);

        if (tensor_id == AUDIO_TENSOR_ID) {
            audio_offset = 0;
        } else if (tensor_count < TOTAL_TENSORS) {
            tensor_count = tensor_id;
            tensor_offsets[tensor_count] = current_offset;
            tensor_sizes[tensor_count] = tensor_size;
            xil_printf("Current Tensor count----------------%d\n", tensor_count);
        }
        expected_fragment_index = 1;
        send_ack(tensor_id, 0, 1);
    } else {
        if (length < ETH_HEADER_SIZE + FRAGMENT_HEADER_SIZE) {
            xil_printf("Subsequent fragment packet too short, length %d\n", length);
            return;
        }
        actual_payload_length = get_u32(header_ptr + 12);
        header_size = FRAGMENT_HEADER_SIZE;

        if (fragment_index != expected_fragment_index) {
            xil_printf("Fragment out of order for tensor %d: expected %d, got %d\n",
                       tensor_id, expected_fragment_index, fragment_index);
            send_ack(tensor_id, expected_fragment_index, 0);
            return;
        } else {
            xil_printf("Received fragment %d for tensor %d with actual payload %d\n",
                       fragment_index, tensor_id, actual_payload_length);
            send_ack(tensor_id, fragment_index, 1);
            expected_fragment_index = fragment_index + 1;
        }
    }

    if (actual_payload_length > (unsigned int)(length - ETH_HEADER_SIZE - header_size)) {
        xil_printf("Warning: actual payload length field (%d) exceeds available bytes (%d).\n",
                   actual_payload_length, length - ETH_HEADER_SIZE - header_size);
        actual_payload_length = length - ETH_HEADER_SIZE - header_size;
    }

    if (tensor_id != AUDIO_TENSOR_ID) {
        memcpy((void*)(DRAM_ptr + current_offset), packet + ETH_HEADER_SIZE + header_size, actual_payload_length);
         current_offset += actual_payload_length;

         xil_printf("Copied %d bytes into DRAM; current_offset now 0x%08X\n", actual_payload_length, current_offset);
    } else {
    	if (audio_offset + actual_payload_length <= AUDIO_BUFFER_SIZE) {
    	            memcpy(AudioInputBuffer + audio_offset, packet + ETH_HEADER_SIZE + header_size, actual_payload_length);
    	            audio_offset += actual_payload_length;
    	            xil_printf("Copied %d bytes into AudioInputBuffer; offset now %d\n", actual_payload_length, audio_offset);

    	            // Mark audio_ready when fully received
    	            if (audio_offset >= AUDIO_BUFFER_SIZE) {
    	                xil_printf("Full audio spectrogram received. Ready for inference.\n");
    	                audio_ready = 1;
    	            }
    	        } else {
    	            xil_printf("AudioInputBuffer overflow detected.\n");
    	        }
    }
}


void receive_model_data() {
    int recv_len = XEmacLite_Recv(&EmacLiteInstance, RecvBuffer);
    if (recv_len > 0) {
        process_packet(RecvBuffer, recv_len);
    }
}

void print_tensor_data() {
    xil_printf("\n--- Tensor Data Verification ---\n");
    for (int i = 0; i < tensor_count+1; i++) {
        xil_printf("Tensor %d stored at offset: 0x%08X, size: %d bytes, DDR_ADDR: 0x%08x \n",
                   i, tensor_offsets[i], tensor_sizes[i], (void*)&DRAM_ptr[tensor_offsets[i]]);
        xil_printf("First 50 bytes of tensor %d: ", i);
        for (int j = 0; j < 50; j++) {
            xil_printf("%02X ", DRAM_ptr[tensor_offsets[i] + j]);
        }
        xil_printf("\n");
    }
    xil_printf("--- End of Verification ---\n");
}

void send_request_to_pc() {
    u8 RequestPacket[14];  // Ethernet header only, no payload
    memcpy(RequestPacket, PC_MAC, 6);  // Destination MAC (PC)
    memcpy(RequestPacket + 6, FPGA_MAC, 6);  // Source MAC (FPGA)
    RequestPacket[12] = (REQUEST_ETHER_TYPE >> 8) & 0xFF;
    RequestPacket[13] = REQUEST_ETHER_TYPE & 0xFF;

    XEmacLite_Send(&EmacLiteInstance, RequestPacket, 14);
    xil_printf("Request sent to PC for recording.\n");
}

// Tensor Structure and Helper Functions for Inference
const char* class_labels[] = {
    "down\n", "go\n", "left\n", "no\n", "right\n",
    "stop\n", "up\n", "yes\n"
};

typedef struct {
    unsigned int tensor_id;
    unsigned int num_dims;
    unsigned int *dims;
    unsigned int data_type;
    unsigned int num_scales;
    float *scales;
    unsigned int num_zero_points;
    int *zero_points;
    unsigned int data_length;
    unsigned char *data;
} Tensor;

void free_tensor(Tensor *tensor) {
    if (tensor) {
        if (tensor->dims) free(tensor->dims);
        if (tensor->scales) free(tensor->scales);
        if (tensor->zero_points) free(tensor->zero_points);
        if (tensor->data) free(tensor->data);
        free(tensor);
    }
}

Tensor* load_tensor_from_dram(unsigned int tensor_index) {
    if (tensor_index >= TOTAL_TENSORS) {
        xil_printf("Invalid tensor index %d\n", tensor_index);
        return NULL;
    }
    unsigned char *ptr = (unsigned char*)(DRAM_ptr + tensor_offsets[tensor_index]);
    Tensor *tensor = (Tensor*)malloc(sizeof(Tensor));
    if (!tensor) {
        xil_printf("Memory allocation failed for Tensor structure.\n");
        return NULL;
    }
    tensor->tensor_id = get_u32(ptr);
    ptr += 4;
    tensor->num_dims = get_u32(ptr);
    ptr += 4;
    tensor->dims = (unsigned int*)malloc(tensor->num_dims * sizeof(unsigned int));
    if (!tensor->dims) {
        xil_printf("Memory allocation failed for dims.\n");
        free(tensor);
        return NULL;
    }
    for (unsigned int i = 0; i < tensor->num_dims; i++) {
        tensor->dims[i] = get_u32(ptr);
        ptr += 4;
    }
    tensor->data_type = get_u32(ptr);
    ptr += 4;
    tensor->num_scales = get_u32(ptr);
    ptr += 4;
    tensor->scales = (float*)malloc(tensor->num_scales * sizeof(float));
    if (!tensor->scales) {
        xil_printf("Memory allocation failed for scales.\n");
        free(tensor->dims);
        free(tensor);
        return NULL;
    }
    for (unsigned int i = 0; i < tensor->num_scales; i++) {
        unsigned int fixed_scale = get_u32(ptr);
        tensor->scales[i] = ((float)fixed_scale) / (1 << 16);
        ptr += 4;
    }
    tensor->num_zero_points = get_u32(ptr);
    ptr += 4;
    tensor->zero_points = (int*)malloc(tensor->num_zero_points * sizeof(int));
    if (!tensor->zero_points) {
        xil_printf("Memory allocation failed for zero_points.\n");
        free(tensor->scales);
        free(tensor->dims);
        free(tensor);
        return NULL;
    }
    for (unsigned int i = 0; i < tensor->num_zero_points; i++) {
        tensor->zero_points[i] = (int)get_u32(ptr);
        ptr += 4;
    }
    tensor->data_length = get_u32(ptr);
    ptr += 4;
    tensor->data = (unsigned char*)malloc(tensor->data_length);
    if (!tensor->data) {
        xil_printf("Memory allocation failed for tensor raw data.\n");
        free_tensor(tensor);
        return NULL;
    }
    memcpy(tensor->data, ptr, tensor->data_length);

    xil_printf("Loaded tensor %d: dims=%d, data_type=%d, data_length=%d\n",
               tensor->tensor_id, tensor->num_dims, tensor->data_type, tensor->data_length);
    return tensor;
}


// Accelerator Integration: Using Two Shared buffer
/*
 * accel_conv3x3_buffer
 *   Writes a 3x3 MAC operation's data into the accelerator's registers
 *   buffer_set = 0 uses buffer 0
 *   buffer_set = 1 uses buffer 1
 *   The control word's bits [16-23] must be set with the PE-selection
 */
void accel_conv3x3_buffer(const int8_t *in_patch, const int8_t *filter,
                          unsigned int buffer_set, uint8_t pe_mask) {


    volatile uint32_t *fptr0, *fptr1, *fptr2;
    volatile uint32_t *iptr0, *iptr1, *iptr2;

    if(buffer_set == 0){
        fptr0 = (volatile uint32_t *)(ACC_FILTER_BASE);
        fptr1 = (volatile uint32_t *)(ACC_FILTER_BASE + 4);
        fptr2 = (volatile uint32_t *)(ACC_FILTER_BASE + 8);

        iptr0 = (volatile uint32_t *)(ACC_INPUT_BASE);
        iptr1 = (volatile uint32_t *)(ACC_INPUT_BASE + 4);
        iptr2 = (volatile uint32_t *)(ACC_INPUT_BASE + 8);
    } else {
        fptr0 = (volatile uint32_t *)(ACC_FILTER_BASE + 24);
        fptr1 = (volatile uint32_t *)(ACC_FILTER_BASE + 28);
        fptr2 = (volatile uint32_t *)(ACC_FILTER_BASE + 32);

        iptr0 = (volatile uint32_t *)(ACC_INPUT_BASE + 24);
        iptr1 = (volatile uint32_t *)(ACC_INPUT_BASE + 28);
        iptr2 = (volatile uint32_t *)(ACC_INPUT_BASE + 32);
    }

    // Pack the 9 filter bytes into three 32-bit words.
    uint32_t filter_word0 = ((unsigned char)filter[0]) |
                            (((unsigned char)filter[1]) << 8) |
                            (((unsigned char)filter[2]) << 16) |
                            (((unsigned char)filter[3]) << 24);
    uint32_t filter_word1 = ((unsigned char)filter[4]) |
                            (((unsigned char)filter[5]) << 8) |
                            (((unsigned char)filter[6]) << 16) |
                            (((unsigned char)filter[7]) << 24);
    // For the 9th filter byte, ensure the upper 24 bits are zero.
    uint32_t filter_word2 = (((uint32_t)( (unsigned char)filter[8] )) & 0x000000FF);

    // Write the 32-bit filter words.
    *fptr0 = filter_word0;
    *fptr1 = filter_word1;
    *fptr2 = filter_word2;

    // Pack the input patch.
    uint32_t input_word0 = ((unsigned char)in_patch[0]) |
                           (((unsigned char)in_patch[1]) << 8) |
                           (((unsigned char)in_patch[2]) << 16) |
                           (((unsigned char)in_patch[3]) << 24);
    uint32_t input_word1 = ((unsigned char)in_patch[4]) |
                           (((unsigned char)in_patch[5]) << 8) |
                           (((unsigned char)in_patch[6]) << 16) |
                           (((unsigned char)in_patch[7]) << 24);
    // Write the first two 32-bit words of the input patch.
    *iptr0 = input_word0;
    *iptr1 = input_word1;

    // Construct and write the control word into the third 32-bit word.
    // Bits [7:0]: 9th input value.
    // Bits [16:23]: must be set to the PE-selection (pe_mask).
    // Bit 24: enable (1).
    // Other bits: 0.
    unsigned int ctrl_word = (pe_mask << 16) | (1 << 24) | (((unsigned char)in_patch[8]) & 0xFF);
    *iptr2 = ctrl_word;
}
/*
 * read_accelerator_results:
 *   Reads 'num_ops' 32-bit results from the accelerator's output region.
 *   Results are read from (ACC_OUTPUT_ADDR + acc_output_offset) and the offset is incremented.
 */
void read_accelerator_results(uint32_t *results, unsigned int num_ops) {
    for (unsigned int i = 0; i < num_ops; i++) {
        volatile uint32_t *out_ptr = (volatile uint32_t *)(ACC_OUTPUT_ADDR + acc_output_offset);
        results[i] = *out_ptr;
        acc_output_offset += 4;
    }
}


// Convolution with Accelerator
/*
 * conv_with_accelerator_parallel:
 *   For each output pixel, processes filters in pairs.
 *   The input patch is extracted once per output pixel.
 *   For each pair of filters, the first operation is queued into buffer 0 and the second into buffer 1,
 *   with appropriate PE-selection (pe_mask in control word).
 */
void conv_with_accelerator_parallel(const int8_t* input, int input_width,
                                    const int8_t* filters, const int32_t* biases,
                                    float S_x, int Z_x, const float* filter_scales,
                                    float S_y, int Z_y,
                                    int8_t* output) {
    // Reset the global accelerator output offset.
    acc_output_offset = 0;

    // For each output pixel.
    for (int oh = 0; oh < CONV1_OUTPUT_HEIGHT; oh++) {
        for (int ow = 0; ow < CONV1_OUTPUT_WIDTH; ow++) {
            // Extract the 3x3 input patch once for this output pixel.
            int8_t in_patch[9];
            for (int r = 0; r < CONV1_KERNEL_HEIGHT; r++) {
                for (int c = 0; c < CONV1_KERNEL_WIDTH; c++) {
                    in_patch[r * CONV1_KERNEL_WIDTH + c] =
                        input[(oh + r) * input_width + (ow + c)];
                }
            }

            // Process the filters in pairs (because we have two register buffers).
            for (int group = 0; group < CONV1_FILTERS; group += 2) {
                int num_ops = ((group + 2) <= CONV1_FILTERS) ? 2 : 1;

                // Queue the first operation into buffer 0.
                {
                    int f = group;
                    uint8_t pe_mask = 1 << (f % 8);  // Set PE-selection bits sequantially
                    accel_conv3x3_buffer(in_patch, &filters[f * 9], 0, pe_mask);
                }

                // If there is a second filter in the pair, queue it into buffer 1.
                if (num_ops == 2) {
                    int f = group + 1;
                    uint8_t pe_mask = 1 << (f % 8);
                    accel_conv3x3_buffer(in_patch, &filters[f * 9], 1, pe_mask);
                }


                // Read the results from the accelerator.
                uint32_t results[2];
                read_accelerator_results(results, num_ops);

                // Post-process and store the results.
                for (int j = 0; j < num_ops; j++) {
                    int f = group + j;
                    int mac = results[j] + biases[f];
                    float multiplier = (S_x * filter_scales[f]) / S_y;
                    int32_t scaled = (int32_t)round(multiplier * mac) + Z_y;
                    if (scaled < 0) scaled = 0;
                    if (scaled > 127) scaled = 127;
                    int out_index = (oh * CONV1_OUTPUT_WIDTH + ow) * CONV1_FILTERS + f;
                    output[out_index] = (int8_t)scaled;
                }
            }
        }
    }
}

// New: conv2_with_accelerator_parallel for Second Convolution Layer
/*
 * conv2_with_accelerator_parallel:
 *   Processes the second convolution layer, where:
 *     - Input: conv1 output, dimensions: 122 x 127 x 32.
 *     - Filters: from Tensor 6, shape: [64, 3, 3, 32] (flattened)
 *     - Biases: from Tensor 7, 64 values.
 *     - Input quantization for conv2: from Tensor 5.
 *     - Output quantization for conv2: from Tensor 8.
 *
 * For each output pixel (with spatial dimensions 120 x 125),
 * for each filter, the convolution is performed over all 32 input channels.
 * The accelerator (which performs a 3x3 MAC on one channel) is invoked for each channel,
 * and the results are accumulated across channels.
 *
 */
void conv2_with_accelerator_parallel(const int8_t* input, int input_width,
    const int8_t* filters, const int32_t* biases,
    float S_x2, int Z_x2, const float* filter_scales,
    float S_y2, int Z_y2,
    int8_t* output) {
    // Reset accelerator output offset.
    // For each output spatial location (conv2 output dimensions: 120 x 125).
    for (int oh = 0; oh < CONV2_OUTPUT_HEIGHT; oh++) {

        for (int ow = 0; ow < CONV2_OUTPUT_WIDTH; ow++) {
            // For each conv2 filter, initialize an accumulator.
            int accumulators[CONV2_FILTERS];
            for (int f = 0; f < CONV2_FILTERS; f++) {
                accumulators[f] = 0;
            }
            // For each input channel (there are 32 channels in conv2 input).
            for (int ch = 0; ch < CONV2_INPUT_CHANNELS; ch++) {
                // Extract the 3x3 patch from the input for channel ch.
                int8_t in_patch[9];
                for (int r = 0; r < CONV2_KERNEL_HEIGHT; r++) {
                    for (int c = 0; c < CONV2_KERNEL_WIDTH; c++) {
                    // Assuming input is in channel-last order:
                    // Index = ((oh + r)*input_width + (ow + c)) * CONV2_INPUT_CHANNELS + ch
                    in_patch[r * CONV2_KERNEL_WIDTH + c] =
                    input[((oh + r) * input_width + (ow + c)) * CONV2_INPUT_CHANNELS + ch];
                    }
                }
                // Process filters in pairs.
                for (int group = 0; group < CONV2_FILTERS; group += 2) {
                    int num_ops = ((group + 2) <= CONV2_FILTERS) ? 2 : 1;
                    // For the first filter in the pair, use buffer 0.
                    {
                    int f = group;
                    // Compute pointer to filter weights for filter f and channel ch.
                    // Each conv2 filter has size 3x3x32; thus for filter f, the weights for channel ch are at:
                    // offset = f * (3*3*CONV2_INPUT_CHANNELS) + ch*9
                    const int8_t *filter_ptr = &filters[f * (CONV2_KERNEL_HEIGHT * CONV2_KERNEL_WIDTH * CONV2_INPUT_CHANNELS) + ch * 9];
                    uint8_t pe_mask = 1 << (f % 8);
                    accel_conv3x3_buffer(in_patch, filter_ptr, 0, pe_mask);
                    }
                    // For the second filter in the pair, use buffer 1.
                    if (num_ops == 2) {
                        int f = group + 1;
                        const int8_t *filter_ptr = &filters[f * (CONV2_KERNEL_HEIGHT * CONV2_KERNEL_WIDTH * CONV2_INPUT_CHANNELS) + ch * 9];
                        uint8_t pe_mask = 1 << (f % 8);
                        accel_conv3x3_buffer(in_patch, filter_ptr, 1, pe_mask);
                        }

                        uint32_t results[2];
                        read_accelerator_results(results, num_ops);
                        // Accumulate the results for the corresponding filters.
                        for (int j = 0; j < num_ops; j++) {
                        int f = group + j;
                        accumulators[f] += results[j];
                        }
                }
            } // End loop over channels.
            // After processing all channels, finish computation for each filter.
            for (int f = 0; f < CONV2_FILTERS; f++) {
                int mac = accumulators[f] + biases[f];
                float multiplier = (S_x2 * filter_scales[f]) / S_y2;
                int32_t scaled = (int32_t)round(multiplier * mac) + Z_y2;
                if (scaled < 0) scaled = 0;
                if (scaled > 127) scaled = 127;
                int out_index = (oh * CONV2_OUTPUT_WIDTH + ow) * CONV2_FILTERS + f;
                output[out_index] = (int8_t)scaled;
            }
        }
    }
}


void maxpool2d(const int8_t* input, int input_height, int input_width, int channels,
int pool_height, int pool_width, int stride, int8_t* output) {
    int output_height = (input_height - pool_height) / stride + 1;
    int output_width = (input_width - pool_width) / stride + 1;
    for (int h = 0; h < output_height; h++) {
        for (int w = 0; w < output_width; w++) {
            for (int ch = 0; ch < channels; ch++) {
                int8_t max_val = -128;  // minimum value for int8_t
                for (int ph = 0; ph < pool_height; ph++) {
                    for (int pw = 0; pw < pool_width; pw++) {
                        int in_h = h * stride + ph;
                        int in_w = w * stride + pw;
                        int index = ((in_h * input_width) + in_w) * channels + ch;
                        int8_t val = input[index];
                        if (val > max_val) {
                        max_val = val;
                        }
                    }
                }
                int out_index = ((h * output_width) + w) * channels + ch;
                output[out_index] = max_val;
            }
        }
    }
}

void fc_with_accelerator_parallel(const int8_t *input, int input_length,
    const int8_t *weights, const int32_t *biases,
    float S_x, int Z_x, const float *weight_scales,
    float S_y, int Z_y,
    int num_outputs,
    int8_t *output) {
    // Compute number of full blocks (each of 9 elements) and remainder.
    int num_full_blocks = input_length / 9;
    int remainder = input_length % 9;

    // For each output neuron.
    for (int m = 0; m < num_outputs; m++) {
        int total_acc = 0;
        // Process each full 9-element block in pairs if possible.
        for (int b = 0; b < num_full_blocks; b += 2) {
            int num_ops = ((b + 2) <= num_full_blocks) ? 2 : 1;
            uint32_t results[2] = {0, 0};
            // Process first block (buffer 0).
            const int8_t *in_block = &input[b * 9];
            const int8_t *w_block = &weights[m * input_length + b * 9];
            // Use a fixed PE-selection mask (modify as needed)
            uint8_t pe_mask = 1 << (m % 8);
            accel_conv3x3_buffer(in_block, w_block, 0, pe_mask);
            // If available, process second block (buffer 1).
            if (num_ops == 2) {
                const int8_t *in_block = &input[(b + 1) * 9];
                const int8_t *w_block = &weights[m * input_length + (b + 1) * 9];
                uint8_t pe_mask = 1 << (m % 8);
                accel_conv3x3_buffer(in_block, w_block, 1, pe_mask);
            }

            read_accelerator_results(results, num_ops);
            for (int j = 0; j < num_ops; j++) {
            total_acc += results[j];
            }
        }

        // If there's a remainder block, process it with padding.
        if (remainder > 0) {
            int8_t padded_block[9];
            int8_t padded_weights[9];
            // Initialize padded_block and padded_weights with zeros.
            memset(padded_block, 0, 9 * sizeof(int8_t));
            memset(padded_weights, 0, 9 * sizeof(int8_t));
            // Copy the remainder values.
            memcpy(padded_block, &input[num_full_blocks * 9], remainder * sizeof(int8_t));
            memcpy(padded_weights, &weights[m * input_length + num_full_blocks * 9], remainder * sizeof(int8_t));
            // Process the padded block.
            uint8_t pe_mask = 0x01;
            accel_conv3x3_buffer(padded_block, padded_weights, 0, pe_mask);
            uint32_t result = 0;
            read_accelerator_results(&result, 1);
            total_acc += result;
        }

        // Add the bias.
        total_acc += biases[m];
        // Compute the quantized output.
        float multiplier = (S_x * weight_scales[0]) / S_y;
        int32_t scaled = (int32_t)round(multiplier * total_acc) + Z_y;
        if (scaled < 0) scaled = 0;
        if (scaled > 127) scaled = 127;
        output[m] = (int8_t)scaled;
    }
}



void softmax(const float *logits, float *probabilities, int num_classes) {
    float max_val = logits[0];
    for (int i = 1; i < num_classes; i++) {
        if (logits[i] > max_val)
        max_val = logits[i];
    }
    float sum = 0.0;
    for (int i = 0; i < num_classes; i++) {
        probabilities[i] = expf(logits[i] - max_val);
        sum += probabilities[i];
    }
    for (int i = 0; i < num_classes; i++) {
        probabilities[i] /= sum;
    }
}

int main() {

    init_platform();
    Xil_DCacheDisable();
    //Initialize UARTLite before inference
	int status = XUartLite_Initialize(&UartLite, UARTLITE_DEVICE_ID);
		if (status != XST_SUCCESS) {
			 xil_printf("UARTLite init failed\n");
		return XST_FAILURE;
	}

    XEmacLite_Initialize(&EmacLiteInstance, XPAR_AXI_ETHERNETLITE_0_DEVICE_ID);
    XEmacLite_SetMacAddress(&EmacLiteInstance, FPGA_MAC);

    xil_printf("FPGA MAC Address Set to: %02X:%02X:%02X:%02X:%02X:%02X\n",
               FPGA_MAC[0], FPGA_MAC[1], FPGA_MAC[2],
               FPGA_MAC[3], FPGA_MAC[4], FPGA_MAC[5]);
    xil_printf("FPGA ready to receive TFLite model data into DRAM at 0x%08X...\n", DRAM_BASE_ADDR);

    // Model param transmission
    // Continuously receive packets until all 18 tensors have been received
    while(1) {
        receive_model_data();
        if (tensor_count >= (TOTAL_TENSORS - 1)) {
            xil_printf("All tensors received. Stopping reception.\n", TOTAL_TENSORS);
            break;
        }
    }

    // Ready to receive audio and inference
    int last_button_state = 0;
    while (1) {
        int button_state = *button & 0x1;
        if (button_state && !last_button_state) {  // Rising edge detected
            xil_printf("Button Press Detected! Sending request to PC...\n");
            send_request_to_pc();
        }
        last_button_state = button_state;

        receive_model_data();


        // Start Conv
        if(audio_ready == 1)
        {
            //Conv
            int input_size = INPUT_HEIGHT * INPUT_WIDTH;

            Tensor *input_qparams = load_tensor_from_dram(2);
            if (!input_qparams) {
                xil_printf("Failed to load input quantization parameters.\n");
                return -1;
            }
            float S_x = input_qparams->scales[0];
            int Z_x = input_qparams->zero_points[0];
            free_tensor(input_qparams);
            input_qparams = NULL;

            Tensor *filter_tensor = load_tensor_from_dram(3);
            if (!filter_tensor) {
                xil_printf("Failed to load filter tensor.\n");
                return -1;
            }
            if (filter_tensor->num_scales != CONV1_FILTERS) {
                xil_printf("Unexpected number of filter scales: %d (expected %d)\n",
                           filter_tensor->num_scales, CONV1_FILTERS);
                free_tensor(filter_tensor);
                filter_tensor = NULL;
                return -1;
            }
            const float *filter_scales = filter_tensor->scales;

            Tensor *bias_tensor = load_tensor_from_dram(4);
            if (!bias_tensor) {
                xil_printf("Failed to load bias tensor.\n");
                free_tensor(filter_tensor);
                filter_tensor = NULL;
                return -1;
            }

            Tensor *output_qparams = load_tensor_from_dram(5);
            if (!output_qparams) {
                xil_printf("Failed to load output quantization parameters.\n");
                free_tensor(filter_tensor);
                free_tensor(bias_tensor);
                filter_tensor = NULL;
                bias_tensor = NULL;
                return -1;
            }
            float S_y = output_qparams->scales[0];
            int Z_y = output_qparams->zero_points[0];
            free_tensor(output_qparams);
            output_qparams = NULL;

            // Allocate output buffer.
            int output_size = CONV1_OUTPUT_HEIGHT * CONV1_OUTPUT_WIDTH * CONV1_FILTERS;
            int8_t *conv1_output = (int8_t*)malloc(output_size * sizeof(int8_t));
            if (!conv1_output) {
                xil_printf("Failed to allocate output buffer.\n");
                free(input);
                input = NULL;
                return -1;
            }
            memset(conv1_output, 0, output_size * sizeof(int8_t));

            // Run the convolution using the accelerator with double buffering (pairwise processing).
            conv_with_accelerator_parallel(AudioInputBuffer, INPUT_WIDTH,
                                           (int8_t*)filter_tensor->data, (int32_t*)bias_tensor->data,
                                           S_x, Z_x, filter_scales,
                                           S_y, Z_y,
                                           conv1_output);

            xil_printf("Conv1 layer completed.\n");

            free_tensor(filter_tensor);
            free_tensor(bias_tensor);
            free(input);
            filter_tensor = NULL;
            bias_tensor = NULL;
            input = NULL;

            // Inference Phase: Second Convolution Layer (conv2)
            // For conv2, the input is the conv1 output.
            // Load conv2 tensors:
            // Tensor 5 is already used for conv1 output quantization.
            // For conv2, we use:
            //   - Tensor 5's quantization for conv2 input quantization.
            //   - Tensor 6: conv2 filter weights and per-channel scales.
            //   - Tensor 7: conv2 biases.
            //   - Tensor 8: conv2 output quantization.

            Tensor *input_qparams2 = load_tensor_from_dram(5);
            if (!input_qparams2) {
                xil_printf("Failed to load conv2 input quantization parameters (from Tensor 5).\n");
                free(conv1_output);
                conv1_output = NULL;
                return -1;
            }
            float S_x2 = input_qparams2->scales[0];
            int Z_x2 = input_qparams2->zero_points[0];
            free_tensor(input_qparams2);
            input_qparams2 = NULL;

            Tensor *filter_tensor2 = load_tensor_from_dram(6);
            if (!filter_tensor2) {
                xil_printf("Failed to load conv2 filter tensor.\n");
                free(conv1_output);
                conv1_output = NULL;
                return -1;
            }
            if (filter_tensor2->num_scales != CONV2_FILTERS) {
                xil_printf("Unexpected number of conv2 filter scales: %d (expected %d)\n",
                           filter_tensor2->num_scales, CONV2_FILTERS);
                free_tensor(filter_tensor2);
                free(conv1_output);
                filter_tensor2 = NULL;
                conv1_output = NULL;
                return -1;
            }
            const float *filter_scales2 = filter_tensor2->scales;

            Tensor *bias_tensor2 = load_tensor_from_dram(7);
            if (!bias_tensor2) {
                xil_printf("Failed to load conv2 bias tensor.\n");
                free_tensor(filter_tensor2);
                free(conv1_output);
                filter_tensor2 = NULL;
                conv1_output = NULL;
                return -1;
            }

            Tensor *output_qparams2 = load_tensor_from_dram(8);
            if (!output_qparams2) {
                xil_printf("Failed to load conv2 output quantization parameters.\n");
                free_tensor(filter_tensor2);
                free_tensor(bias_tensor2);
                free(conv1_output);
                filter_tensor2 = NULL;
                bias_tensor2 = NULL;
                conv1_output = NULL;
                return -1;
            }
            float S_y2 = output_qparams2->scales[0];
            int Z_y2 = output_qparams2->zero_points[0];
            free_tensor(output_qparams2);
            output_qparams2 = NULL;

            // Allocate output buffer for conv2.
            int conv2_output_size = CONV2_OUTPUT_HEIGHT * CONV2_OUTPUT_WIDTH * CONV2_FILTERS;
            int8_t *conv2_output = (int8_t*)malloc(conv2_output_size * sizeof(int8_t));
            if (!conv2_output) {
                xil_printf("Failed to allocate conv2 output buffer.\n");
                free(conv1_output);
                free_tensor(filter_tensor2);
                free_tensor(bias_tensor2);
                conv1_output = NULL;
                filter_tensor2 = NULL;
                bias_tensor2 = NULL;
                return -1;
            }
            memset(conv2_output, 0, conv2_output_size * sizeof(int8_t));

            conv2_with_accelerator_parallel(conv1_output, CONV1_OUTPUT_WIDTH,
                                            (int8_t*)filter_tensor2->data, (int32_t*)bias_tensor2->data,
                                            S_x2, Z_x2, filter_scales2,
                                            S_y2, Z_y2,
                                            conv2_output);

            xil_printf("Conv2 layer completed.\n");

            free(conv1_output);
            free_tensor(filter_tensor2);
            free_tensor(bias_tensor2);
            conv1_output = NULL;
            filter_tensor2 = NULL;
            bias_tensor2 = NULL;


            // MaxPool2D and Flatten Layers
            // For conv2 output dimensions: 120 x 125 x 64
            // Using a 2x2 pool with stride 2 produces:
            int pool_height = 2, pool_width = 2, pool_stride = 2;
            int pool_output_height = (CONV2_OUTPUT_HEIGHT - pool_height) / pool_stride + 1; // should be 60
            int pool_output_width = (CONV2_OUTPUT_WIDTH - pool_width) / pool_stride + 1;    // should be 62
            int pool_output_size = pool_output_height * pool_output_width * CONV2_FILTERS;
            int8_t *pool_output = (int8_t*)malloc(pool_output_size * sizeof(int8_t));
            if (!pool_output) {
                xil_printf("Failed to allocate pool output buffer.\n");
                free(conv2_output);
                conv2_output = NULL;
                return -1;
            }

            maxpool2d(conv2_output, CONV2_OUTPUT_HEIGHT, CONV2_OUTPUT_WIDTH, CONV2_FILTERS,
                      pool_height, pool_width, pool_stride, pool_output);

            free(conv2_output);
            conv2_output = NULL;


            xil_printf("MaxPool2D and Flatten layers completed.\n");

            /* Fully Connected Layer # 1 */
            // For the FC layer:
            //   - Tensor 10: FC input quantization parameters.
            //   - Tensor 11: FC weights, with dimensions 128 x flattened_size.
            //   - Tensor 12: FC biases (128 values).
            //   - Tensor 13: FC output quantization parameters.

           Tensor *fc_in_qparams = load_tensor_from_dram(10);
            if (!fc_in_qparams) { xil_printf("Failed to load FC input quantization (Tensor 10).\n"); free(pool_output); return -1; }
                float S_x_fc = fc_in_qparams->scales[0];
                int Z_x_fc = fc_in_qparams->zero_points[0];
                free_tensor(fc_in_qparams);
                fc_in_qparams = NULL;

           Tensor *fc_weight_tensor = load_tensor_from_dram(11);
            if (!fc_weight_tensor) {
               xil_printf("Failed to load FC weight tensor (Tensor 11).\n");
               free(pool_output);
               return -1; }

            const float *fc_weight_scales = fc_weight_tensor->scales;

            Tensor *fc_bias_tensor = load_tensor_from_dram(12);
            if (!fc_bias_tensor) {
               xil_printf("Failed to load FC bias tensor (Tensor 12).\n");
               free(pool_output);
               free_tensor(fc_weight_tensor);
               return -1; }

            int flattened_size = pool_output_height * pool_output_width * CONV2_FILTERS;

            Tensor *fc_out_qparams = load_tensor_from_dram(13);
            if (!fc_out_qparams) {
               xil_printf("Failed to load FC output quantization (Tensor 13).\n");
               free(pool_output);
               free_tensor(fc_weight_tensor);
               free_tensor(fc_bias_tensor);
               return -1;
            }
            float S_y_fc = fc_out_qparams->scales[0];
            int Z_y_fc = fc_out_qparams->zero_points[0];
            free_tensor(fc_out_qparams);
            fc_out_qparams = NULL;

            // Allocate FC output buffer: FC layer has 128 outputs.
            int8_t *fc1_output = (int8_t*)malloc(FC1_OUTPUT_SIZE * sizeof(int8_t));
            if (!fc1_output) {
                xil_printf("Failed to allocate FC output buffer.\n");
                free(pool_output);
            }

            fc_with_accelerator_parallel(pool_output, flattened_size,
                                         (int8_t*)fc_weight_tensor->data, (int32_t*)fc_bias_tensor->data,
                                         S_x_fc, Z_x_fc, fc_weight_scales,
                                         S_y_fc, Z_y_fc,
                                         FC1_OUTPUT_SIZE,
                                         fc1_output);

            xil_printf("Fully Connected 1 completed.\n");
            free(pool_output);

            pool_output = NULL;

            /* Fully Connected Layer 2 */
            // FC2 uses:
            // - Tensor 13 (reinterpreted): FC2 input quantization.
            // - Tensor 14: FC2 weights, dimensions: [FC2_OUTPUT_SIZE, FC1_OUTPUT_SIZE].
            // - Tensor 15: FC2 biases (FC2_OUTPUT_SIZE values).
            // - Tensor 16: FC2 output quantization.
        
           Tensor *fc2_in_qparams = load_tensor_from_dram(13);
           if (!fc2_in_qparams) {
               xil_printf("Failed to load FC2 input quantization (Tensor 13).\n");
               free(fc1_output); return -1;
           }
           float S_x_fc2 = fc2_in_qparams->scales[0];
           int Z_x_fc2 = fc2_in_qparams->zero_points[0];
           free_tensor(fc2_in_qparams);
           fc2_in_qparams = NULL;

            Tensor *fc2_weight_tensor = load_tensor_from_dram(14);
            if (!fc2_weight_tensor) {
               xil_printf("Failed to load FC2 weight tensor (Tensor 14).\n");
               free(fc1_output);
               return -1;
            }
            const float *fc2_weight_scales = fc2_weight_tensor->scales;

            Tensor *fc2_bias_tensor = load_tensor_from_dram(15);
            if (!fc2_bias_tensor) {
               xil_printf("Failed to load FC2 bias tensor (Tensor 15).\n");
               free(fc1_output); f
               ree_tensor(fc2_weight_tensor);
               return -1;
            }

            Tensor *fc2_out_qparams = load_tensor_from_dram(16);
            if (!fc2_out_qparams) {
               xil_printf("Failed to load FC2 output quantization (Tensor 16).\n");
               free(fc1_output);
               free_tensor(fc2_weight_tensor);
               free_tensor(fc2_bias_tensor);
               return -1;
            }
            float S_y_fc2 = fc2_out_qparams->scales[0];
            int Z_y_fc2 = fc2_out_qparams->zero_points[0];
            free_tensor(fc2_out_qparams);



            int8_t *fc2_output = (int8_t*)malloc(FC2_OUTPUT_SIZE * sizeof(int8_t));
            if (!fc2_output) {
                xil_printf("Failed to allocate FC2 output buffer.\n");
                free(fc1_output);
                return -1;
            }

            fc_with_accelerator_parallel(fc1_output, FC1_OUTPUT_SIZE,
                                         (int8_t*)fc2_weight_tensor->data, (int32_t*)fc2_bias_tensor->data,
                                         S_x_fc2, Z_x_fc2, fc2_weight_scales,
                                         S_y_fc2, Z_y_fc2,
                                         FC2_OUTPUT_SIZE,
                                         fc2_output);

            xil_printf("Fully Connected 2 completed.\n");

            /* ----- Output Prediction ----- */
            // Convert FC2 outputs to probabilities using softmax.
            float fc2_logits[FC2_OUTPUT_SIZE];
            // Dequantize FC2 output
            for (int i = 0; i < FC2_OUTPUT_SIZE; i++) {
                fc2_logits[i] = S_x_fc2 * ((int)fc2_output[i] - Z_x_fc2);
            }
            float probabilities[FC2_OUTPUT_SIZE];
            softmax(fc2_logits, probabilities, FC2_OUTPUT_SIZE);

            xil_printf("Inference completed.\n");

            // Choose predicted class (argmax).
            int predicted_class = 0;
            float max_prob = probabilities[0];
            for (int i = 1; i < FC2_OUTPUT_SIZE; i++) {
                if (probabilities[i] > max_prob) {
                    max_prob = probabilities[i];
                    predicted_class = i;
                }
            }
            // convert probability to percentage and write to seven segment display
            max_prob = max_prob * 100;
            *seg_ptr = (uint32_t) max_prob;

			// Send predicted command string over Bluetooth 10 times aviod miss packet
            const char *cmd = class_labels[predicted_class];;
            for(int i = 0; i < 10; i++) {
            	XUartLite_Send(&UartLite, (u8 *)cmd, strlen(cmd));
            	usleep(1000);
            }

            xil_printf("Predicted class: %s (probability: %d)\n", class_labels[predicted_class], (int)(max_prob));

			// Debug print (optional)
			xil_printf("Command sent to GUI: %s\n", cmd);

            // Free remaining FC2 tensors.
            free(fc1_output);
            free(fc2_output);


            audio_offset = 0; // Clear to receive next audio
            audio_ready = 0;
            expected_fragment_index = 0;
        }
    }



    cleanup_platform();
    return 0;
}
