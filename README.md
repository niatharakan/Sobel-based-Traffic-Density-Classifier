# Real-Time Traffic Density Classification using FPGA and Image Processing

## Project Overview
This project implements a **real-time traffic density classification system** using **image processing techniques** and **FPGA hardware**.  
The system classifies traffic into **Low, Medium, or High** density and displays the result using **LEDs** and a **7-segment display**.  

The goal is to provide a **cost-effective, automated solution** for traffic monitoring and management.

---

## Motivation
Traffic congestion is a major issue in urban areas.  
Current systems often rely on **fixed signal timings** or **manual monitoring**, leading to:  
- Unnecessary waiting at empty intersections  
- Increased congestion during peak hours  
- Higher fuel consumption and pollution  

This project demonstrates a **real-time, automated solution** that integrates **FPGA hardware** with **image processing logic** for efficient traffic management.

---

## Problem Statement
- Most traffic signals are **non-automated or human-dependent**, which is inefficient.  
- Real-time traffic monitoring is either **expensive** or **complex**.  
- There is a need for a **simple, reliable, and scalable solution** to classify traffic density automatically.

---

## Solution Approach
1. Capture traffic images and apply **edge detection** to estimate vehicle density.  
2. Classify traffic into **Low, Medium, or High** based on detected density.  
3. Display the classification result on **FPGA LEDs** and a **7-segment display**.  
4. Implement the logic using **Verilog** and simulate using a **UART testbench**.  

---

## System Features
- Real-time traffic density classification  
- Visual output via **LEDs and 7-segment display**  
- FPGA-based implementation for **fast and hardware-level processing**  
- Easily extendable to **live camera feeds** and **smart traffic control systems**

---

## Hardware Components
- FPGA development board (Vivado compatible)  
- LEDs (4 for traffic status)  
- 7-segment display for countdown timer  
- UART interface for testing  

---

## Software & Tools
- **Vivado 2022/2023** – for Verilog design, synthesis, and simulation  
- **Verilog HDL** – for implementing UART receiver, traffic logic, and display  
- **Simulation Testbench** – to verify UART communication and traffic classification

---

## Usage Instructions
1. Open the Vivado project.  
2. Add the following files to the project:
   - `traffic_uart.v` (top module)  
   - `uart_rx.v` (UART receiver)  
   - `seg7_decoder.v` (7-segment decoder)  
   - `traffic_uart_tb.v` (testbench)  
3. Set `traffic_uart_tb` as **Top Module** in Simulation Sources.  
4. Run **Behavioral Simulation**.  
5. Observe traffic classification via:
   - LED outputs (`led[3:0]`)  
   - Countdown on 7-segment display (`D0_AN`, `D0_SEG`)  
6. Send UART data bytes (`48='0', 49='1', 50='2', 51='3'`) in the testbench to simulate different traffic levels.

---

## Traffic Classification Mapping
| UART Byte | Traffic Level | LED Output | Countdown Timer |
|------------|---------------|------------|----------------|
| 48 (`0`)   | HIGH          | 0001       | 5s             |
| 49 (`1`)   | MEDIUM        | 0010       | 10s            |
| 50 (`2`)   | LOW           | 0100       | 15s            |
| 51 (`3`)   | EMERGENCY     | 1111       | 0s (instant)   |

---

## Future Scope
- Integrate **live camera feeds** for real traffic monitoring  
- Implement **smart signal control** based on traffic density  
- Extend to **multi-lane and multi-intersection systems**  
- Optimize **FPGA resource usage** for larger scale deployment

