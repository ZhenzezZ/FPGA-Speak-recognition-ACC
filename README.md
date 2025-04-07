Overview
This project implements a hardware-accelerated keyword speech recognition system using the Nexys4 DDR FPGA platform. A machine learning model is deployed directly onto the FPGA to perform inference with improved performance. The platform incorporates several components, including a Bluetooth BT2 module, DDR DRAM, Ethernet communication with an external PC, and a soft-core processor (MicroBlaze). During inference, preprocessed speech data is transmitted from the PC to the FPGA via Ethernet, and the recognized keyword is sent back via Bluetooth. Additionally, the model's confidence score is shown on the seven-segment display. The system highlights how custom hardware can be used to accelerate speech recognition tasks in a resource-constrained environment.
Design Tree
Our files are organized into 4 main subfolders on the GitHub repository as follows: 
* doc: PDF of project final report, final demo presentation slides, and demo video
* PC_code: Python files that are run on external PC devices such as the jupyter notebook for model pre-training, script that is responsible for capturing/preprocessing audio input and Ethernet data (model parameters & audio input) transmission, stickman GUI and Bluetooth integration script. 
* Microblaze: main C code (receiving model parameters/input audio data & inference) that runs on the Microblaze
* Hardware_Design: Verilog files for accelerator and constraint files

Demo video: https://youtu.be/AowOfI-H4cw
