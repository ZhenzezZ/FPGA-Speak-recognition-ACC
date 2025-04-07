import pyaudio
import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import get_window
import cv2
import os
import time
import struct
from scapy.all import Ether, sendp, sniff

RATE = 16000
FRAME_LEN = 255
FRAME_STEP = 128
FFT_LEN = 256
TARGET_SHAPE = (124, 129)
NORM_MEAN = -18.7
NORM_STD = 9.5
INPUT_SCALE = 0.0078125
INPUT_ZERO_POINT = 128

interface = "\\Device\\NPF_{FB02CD7F-5E2D-4937-9D17-ADF4E6CA12C5}"
dest_mac = "02:AA:BB:CC:DD:EE"
src_mac = "9C:EB:E8:AE:7E:F5"
ethertype = 0x88B5
request_type = 0x88B6
ACK_ETHER_TYPE = 0x88B7

FRAGMENT_SIZE = 1400
FRAGMENT_HEADER_FORMAT_FIRST = "<IIIII"
FRAGMENT_HEADER_SIZE_FIRST = struct.calcsize(FRAGMENT_HEADER_FORMAT_FIRST)
FRAGMENT_HEADER_FORMAT = "<IIII"
FRAGMENT_HEADER_SIZE = struct.calcsize(FRAGMENT_HEADER_FORMAT)
ACK_FORMAT = "<IIB3x"
DELAY_BETWEEN_PACKETS = 0.005

def plot_waveform(audio_data):
    plt.figure(figsize=(10, 4))
    plt.plot(audio_data)
    plt.title('Audio Waveform')
    plt.xlabel('Sample Index')
    plt.ylabel('Amplitude')
    plt.grid()
    plt.show()

def plot_spectrogram(spectrogram):
    plt.figure(figsize=(6, 6))
    plt.imshow(spectrogram, aspect='auto', origin='lower', cmap='viridis')
    plt.colorbar(label='Intensity [dB]')
    plt.title('Spectrogram Sent to FPGA')
    plt.xlabel('Time Frames')
    plt.ylabel('Frequency Bins')
    plt.tight_layout()
    plt.show()

def record_audio(duration=1):
    CHUNK = FRAME_STEP
    total_samples = FRAME_LEN + (duration * RATE - FRAME_LEN) // FRAME_STEP * FRAME_STEP
    audio = pyaudio.PyAudio()
    stream = audio.open(format=pyaudio.paInt16, channels=1, rate=RATE, input=True, frames_per_buffer=CHUNK)
    frames = []
    print("Start recording for 2s...")
    while len(frames) * CHUNK < total_samples:
        data = stream.read(CHUNK, exception_on_overflow=False)
        frames.append(np.frombuffer(data, dtype=np.int16))
    print("Recording finished.")
    stream.stop_stream()
    stream.close()
    audio.terminate()
    audio_data = np.concatenate(frames)[:total_samples]
    return audio_data.astype(np.float32) / 32768.0

def preprocess_for_fpga(waveform):
    frames = []
    for i in range(0, len(waveform) - FRAME_LEN + 1, FRAME_STEP):
        frame = waveform[i:i + FRAME_LEN]
        if len(frame) < FFT_LEN:
            frame = np.pad(frame, (0, FFT_LEN - len(frame)))
        window = get_window('hann', FRAME_LEN)
        frame_windowed = frame[:FRAME_LEN] * window
        fft = np.fft.rfft(frame_windowed, n=FFT_LEN)
        mag = np.abs(fft)
        frames.append(mag)
    spectrogram = np.array(frames).T
    log_spectrogram = np.log(spectrogram + 1e-8)
    normalized = (log_spectrogram - NORM_MEAN) / NORM_STD
    resized = cv2.resize(normalized, TARGET_SHAPE[::-1], interpolation=cv2.INTER_CUBIC)
    quantized = np.clip(resized / INPUT_SCALE + INPUT_ZERO_POINT, 0, 255).astype(np.uint8)
    return quantized, resized


def send_frame(payload):
    """Creates and sends an Ethernet frame with the given payload,
       then waits briefly."""
    frame = Ether(dst=dest_mac, src=src_mac, type=ethertype) / payload
    sendp(frame, iface=interface, verbose=True)
    time.sleep(DELAY_BETWEEN_PACKETS)

def wait_for_ack(tensor_id, fragment_index, timeout=1):
    def ack_filter(pkt):
        if pkt.haslayer(Ether) and pkt.type == ACK_ETHER_TYPE:
            payload = bytes(pkt.payload)
            # Expect at least 9 bytes: 4 for tensor_id, 4 for fragment_index, 1 for status.
            if len(payload) >= 9:
                ack_tensor_id, ack_frag_idx, status = struct.unpack("<IIB", payload[:9])
                return (ack_tensor_id == tensor_id)
        return False

    pkts = sniff(iface=interface, timeout=timeout, lfilter=ack_filter, count=1)
    if pkts:
        payload = bytes(pkts[0].payload)
        ack_tensor_id, ack_frag_idx, status = struct.unpack("<IIB", payload[:9])
        if ack_frag_idx == fragment_index and status == 1:
            return (True, fragment_index)
        else:
            print(f"Received NACK for tensor {tensor_id} fragment {fragment_index}. Receiver expects fragment {ack_frag_idx}.")
            return (False, ack_frag_idx)
    return (False, fragment_index)

def send_tensor_fragments(tensor_id, tensor_payload):
    total_length = len(tensor_payload)
    
    # Compute available payload sizes:
    # For the first fragment:
    max_payload_first = FRAGMENT_SIZE - FRAGMENT_HEADER_SIZE_FIRST
    # For subsequent fragments:
    max_payload_normal = FRAGMENT_SIZE - FRAGMENT_HEADER_SIZE

    # Calculate total number of fragments based on actual data length.
    if total_length <= max_payload_first:
        total_fragments = 1
    else:
        remaining = total_length - max_payload_first
        total_fragments = 1 + (remaining + max_payload_normal - 1) // max_payload_normal

    current_frag = 0
    while current_frag < total_fragments:
        if current_frag == 0:
            data = tensor_payload[:max_payload_first]
            header = struct.pack(
                FRAGMENT_HEADER_FORMAT_FIRST,
                tensor_id,         # Tensor ID.
                0,                 # Fragment index 0.
                total_fragments,   # Total fragments.
                total_length,      # Overall tensor size.
                len(data)          # Actual payload length in this fragment.
            )
        else:
            start = max_payload_first + (current_frag - 1) * max_payload_normal
            end = min(start + max_payload_normal, total_length)
            data = tensor_payload[start:end]
            header = struct.pack(
                FRAGMENT_HEADER_FORMAT,
                tensor_id,
                current_frag,
                total_fragments,
                len(data)          # Actual payload length in this fragment.
            )
        full_payload = header + data

        # Send the fragment first.
        send_frame(full_payload)
        print(f"Sent fragment {current_frag+1}/{total_fragments} for tensor {tensor_id}.")
        
        # Now wait for ACK for the current fragment.
        ack_received, new_frag = wait_for_ack(tensor_id, current_frag)
        if ack_received:
            print(f"ACK received for tensor {tensor_id} fragment {current_frag}.")
            current_frag += 1  # Move to next fragment.
        else:
            # If the receiver indicates a different fragment is expected, update current_frag.
            if new_frag != current_frag:
                print(f"Receiver expects fragment {new_frag} for tensor {tensor_id}. Resending that fragment.")
                current_frag = new_frag
            else:
                print(f"No ACK for tensor {tensor_id} fragment {current_frag}. Resending...")
            # The while loop will repeat and resend the current fragment.

def listen_for_fpga_request():
    print("Listening for FPGA button press requests...")
    while True:
        def packet_callback(packet):
            if packet.haslayer(Ether) and packet[Ether].type == request_type:
                print("Received FPGA request. Starting recording...")
                audio_data = record_audio()
                spectrogram, processed_spectrogram = preprocess_for_fpga(audio_data)
                plot_spectrogram(processed_spectrogram)
                payload = spectrogram.flatten().tobytes()
                tensor_id = 99  # Use a different ID for input audio than model weights
                send_tensor_fragments(tensor_id, payload)

        sniff(iface=interface, prn=packet_callback, store=0, count=1)

def send_tensors_from_binary(binary_file):
    """
    Reads the binary file containing all tensors, parses each tensor's information,
    and sends its binary payload over Ethernet in one or more fragments.
    Each fragment header includes an actual payload length field.
    """
    with open(binary_file, "rb") as f:
        # Read the number of tensors (first 4 bytes)
        num_tensors_data = f.read(4)
        if len(num_tensors_data) < 4:
            print("Binary file is too short.")
            return
        num_tensors = struct.unpack("<I", num_tensors_data)[0]
        print(f"Number of tensors in binary file: {num_tensors}")

        for t in range(num_tensors):
            tensor_start = f.tell()  # Mark the start of this tensor's block

            # tensor ID
            tensor_id_data = f.read(4)
            if len(tensor_id_data) < 4:
                print("Unexpected end of file while reading tensor ID.")
                break
            tensor_id = struct.unpack("<I", tensor_id_data)[0]

            # number of dimensions
            num_dims = struct.unpack("<I", f.read(4))[0]
            for _ in range(num_dims):
                f.read(4)

            # data type code
            f.read(4)

            # quantization parameters
            num_scales = struct.unpack("<I", f.read(4))[0]
            for _ in range(num_scales):
                f.read(4)

            # zero points (4 bytes) and each zero point (4 bytes each)
            num_zero_points = struct.unpack("<I", f.read(4))[0]
            for _ in range(num_zero_points):
                f.read(4)

            # data length (4 bytes)
            data_length = struct.unpack("<I", f.read(4))[0]
            
            f.seek(data_length, 1)

            tensor_end = f.tell()
            tensor_size = tensor_end - tensor_start
            f.seek(tensor_start)
            tensor_payload = f.read(tensor_size)
            f.seek(tensor_end)

            if len(tensor_payload) <= FRAGMENT_SIZE - FRAGMENT_HEADER_SIZE_FIRST:
                # Tensor fits in one frame.
                header = struct.pack(
                    FRAGMENT_HEADER_FORMAT_FIRST,
                    tensor_id,
                    0,
                    1,  # Only one fragment.
                    len(tensor_payload),  # Overall tensor size.
                    len(tensor_payload)   # Actual payload length.
                )
                full_payload = header + tensor_payload
                ack_received, new_frag = wait_for_ack(tensor_id, 0)
                while not ack_received:
                    send_frame(full_payload)
                    print(f"Sent tensor {tensor_id} in one frame, size {len(tensor_payload)} bytes.")
                    ack_received, new_frag = wait_for_ack(tensor_id, 0)
                    if not ack_received:
                        print(f"No ACK for tensor {tensor_id} (single frame). Resending...")
            else:
                send_tensor_fragments(tensor_id, tensor_payload)
            print(f"Finished sending tensor {tensor_id}.")

if __name__ == "__main__":
    binary_file_path = "C:/Users/Zhenz/OneDrive/Desktop/ECE532/model_paramsNew.bin"
    send_tensors_from_binary(binary_file_path)
    listen_for_fpga_request()