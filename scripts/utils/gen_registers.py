#!/usr/bin/env python3
"""
Audio Codec Register Generator

This tool automatically generates:
- SystemVerilog register modules
- C/C++ header files
- Python test scripts
- Documentation

Based on JSON register map configuration.
"""

import json
import argparse
import sys
from pathlib import Path
from typing import Dict, List, Any
from datetime import datetime

class RegisterGenerator:
    """Register code generator"""
    
    def __init__(self, json_file: str):
        self.json_file = Path(json_file)
        self.config = self._load_config()
        self.output_dir = Path("generated")
        self.output_dir.mkdir(exist_ok=True)
        
    def _load_config(self) -> Dict[str, Any]:
        """Load JSON configuration"""
        if not self.json_file.exists():
            raise FileNotFoundError(f"Register map file not found: {self.json_file}")
            
        with open(self.json_file, 'r') as f:
            return json.load(f)
    
    def generate_all(self):
        """Generate all output files"""
        print(f"Generating register files from {self.json_file}")
        
        # Generate SystemVerilog
        self.generate_systemverilog()
        
        # Generate C header
        self.generate_c_header()
        
        # Generate Python test
        self.generate_python_test()
        
        # Generate documentation
        self.generate_documentation()
        
        print("Register generation completed!")
    
    def generate_systemverilog(self):
        """Generate SystemVerilog register module"""
        reg_map = self.config["register_map"]
        module_name = f"{reg_map['module_name']}_regs"
        
        sv_content = f'''/*
 * Auto-generated SystemVerilog Register Module
 * Generated from: {self.json_file.name}
 * Generated on: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
 * 
 * DO NOT EDIT MANUALLY - This file is auto-generated
 */

module {module_name} #(
    parameter ADDR_WIDTH = {reg_map["address_width"]},
    parameter DATA_WIDTH = {reg_map["data_width"]},
    parameter string REG_MAP_FILE = "{self.json_file.name}"
) (
    input  logic                     clk,
    input  logic                     rst_n,
    
    // Register Interface
    input  logic [ADDR_WIDTH-1:0]   reg_addr,
    input  logic [DATA_WIDTH-1:0]   reg_wdata,
    output logic [DATA_WIDTH-1:0]   reg_rdata,
    input  logic                     reg_wen,
    input  logic                     reg_ren,
    output logic                     reg_ready,
    output logic                     reg_error,
    
    // Configuration Outputs
'''
        
        # Generate configuration outputs
        config_signals = [
            "output logic [31:0] config_sample_rate",
            "output logic [31:0] config_bitrate", 
            "output logic [31:0] config_frame_length",
            "output logic [3:0]  config_channels",
            "output logic [1:0]  config_codec_type",
            "output logic [1:0]  config_mode",
            "output logic        config_enable",
            "output logic        config_start",
            "output logic        config_soft_reset",
            "output logic        config_irq_enable"
        ]
        
        for signal in config_signals:
            sv_content += f"    {signal},\n"
        
        # Generate status inputs
        sv_content += "\n    // Status Inputs\n"
        status_signals = [
            "input  logic [31:0] status_main",
            "input  logic [31:0] status_irq", 
            "input  logic [31:0] status_frame_count",
            "input  logic [31:0] status_perf_counter",
            "input  logic [31:0] status_debug0",
            "input  logic [31:0] status_debug1"
        ]
        
        for signal in status_signals:
            sv_content += f"    {signal},\n"
        
        # Generate buffer and interrupt signals
        sv_content += """
    // Buffer Configuration
    output logic [31:0] input_buffer_addr,
    output logic [31:0] output_buffer_addr,
    output logic [15:0] input_buffer_size,
    output logic [15:0] output_buffer_size,
    
    // Interrupt Status
    input  logic        irq_frame_done,
    input  logic        irq_encode_done,
    input  logic        irq_decode_done,
    input  logic        irq_error_in
);

    // Register definitions
"""
        
        # Generate register definitions
        for reg in reg_map["registers"]:
            reg_name = reg["name"].lower()
            sv_content += f"    logic [DATA_WIDTH-1:0] {reg_name};\n"
        
        # Generate register access logic
        sv_content += """
    // Register access logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all registers to default values
"""
        
        for reg in reg_map["registers"]:
            reg_name = reg["name"].lower()
            reset_val = reg["reset_value"]
            sv_content += f"            {reg_name} <= {reset_val};\n"
        
        sv_content += "            reg_ready <= 1'b0;\n"
        sv_content += "            reg_error <= 1'b0;\n"
        sv_content += "        end else begin\n"
        sv_content += "            reg_ready <= 1'b1;\n"
        sv_content += "            reg_error <= 1'b0;\n"
        sv_content += "            \n"
        sv_content += "            // Write operations\n"
        sv_content += "            if (reg_wen) begin\n"
        sv_content += "                case (reg_addr)\n"
        
        # Generate write case statements
        for reg in reg_map["registers"]:
            if reg["access"] in ["RW", "WO"]:
                reg_name = reg["name"].lower()
                addr = reg["address"]
                sv_content += f"                    {addr}: {reg_name} <= reg_wdata;\n"
        
        sv_content += "                    default: reg_error <= 1'b1;\n"
        sv_content += "                endcase\n"
        sv_content += "            end\n"
        sv_content += "            \n"
        
        # Generate status register updates
        sv_content += "            // Update status registers\n"
        status_regs = {
            "reg_status": "status_main",
            "reg_irq_status": "status_irq",
            "reg_frame_count": "status_frame_count", 
            "reg_perf_counter": "status_perf_counter",
            "reg_debug0": "status_debug0",
            "reg_debug1": "status_debug1"
        }
        
        for reg_name, status_signal in status_regs.items():
            sv_content += f"            {reg_name} <= {status_signal};\n"
        
        sv_content += "        end\n"
        sv_content += "    end\n"
        sv_content += "    \n"
        
        # Generate read logic
        sv_content += "    // Read operations\n"
        sv_content += "    always_comb begin\n"
        sv_content += "        reg_rdata = 32'h0;\n"
        sv_content += "        if (reg_ren) begin\n"
        sv_content += "            case (reg_addr)\n"
        
        for reg in reg_map["registers"]:
            reg_name = reg["name"].lower()
            addr = reg["address"]
            sv_content += f"                {addr}: reg_rdata = {reg_name};\n"
        
        sv_content += "                default: reg_rdata = 32'h0;\n"
        sv_content += "            endcase\n"
        sv_content += "        end\n"
        sv_content += "    end\n"
        sv_content += "    \n"
        
        # Generate output assignments
        sv_content += "    // Configuration output assignments\n"
        config_assigns = [
            ("config_sample_rate", "reg_sample_rate"),
            ("config_bitrate", "reg_bitrate"),
            ("config_frame_length", "reg_frame_len"),
            ("config_channels", "reg_channels[3:0]"),
            ("config_codec_type", "reg_control[5:4]"),
            ("config_mode", "reg_control[3:2]"),
            ("config_enable", "reg_control[0]"),
            ("config_start", "reg_control[1]"),
            ("config_soft_reset", "reg_control[7]"),
            ("config_irq_enable", "reg_control[6]"),
            ("input_buffer_addr", "reg_input_addr"),
            ("output_buffer_addr", "reg_output_addr"),
            ("input_buffer_size", "reg_buffer_size[15:0]"),
            ("output_buffer_size", "reg_buffer_size[31:16]")
        ]
        
        for output_name, reg_field in config_assigns:
            sv_content += f"    assign {output_name} = {reg_field};\n"
        
        sv_content += "\nendmodule\n"
        
        # Write to file
        output_file = self.output_dir / f"{module_name}.sv"
        with open(output_file, 'w') as f:
            f.write(sv_content)
        
        print(f"Generated SystemVerilog: {output_file}")
    
    def generate_c_header(self):
        """Generate C header file"""
        reg_map = self.config["register_map"]
        module_name = reg_map["module_name"].upper()
        
        header_content = f'''/*
 * Auto-generated C Header File for {reg_map["description"]}
 * Generated from: {self.json_file.name}
 * Generated on: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
 * 
 * DO NOT EDIT MANUALLY - This file is auto-generated
 */

#ifndef {module_name}_REGS_H
#define {module_name}_REGS_H

#include <stdint.h>

/* Version Information */
#define {module_name}_VERSION_MAJOR  {reg_map["version"].split('.')[0]}
#define {module_name}_VERSION_MINOR  {reg_map["version"].split('.')[1]}
#define {module_name}_VERSION_PATCH  {reg_map["version"].split('.')[2]}

/* Register Addresses */
'''
        
        # Generate register address defines
        for reg in reg_map["registers"]:
            reg_name = reg["name"]
            addr = reg["address"]
            description = reg["description"]
            header_content += f"#define {reg_name:<25} {addr:<10}  /* {description} */\n"
        
        header_content += "\n/* Register Field Definitions */\n"
        
        # Generate field definitions
        for reg in reg_map["registers"]:
            reg_name = reg["name"]
            if "fields" in reg:
                for field in reg["fields"]:
                    field_name = f"{reg_name}_{field['name']}"
                    bits = field["bits"]
                    
                    if ":" in bits:
                        # Multi-bit field
                        high, low = bits.split(":")
                        high, low = int(high), int(low)
                        width = high - low + 1
                        mask = (1 << width) - 1
                        header_content += f"#define {field_name}_SHIFT {low:>15}\n"
                        header_content += f"#define {field_name}_MASK  0x{mask:08X}\n"
                        header_content += f"#define {field_name}_GET(x)   (((x) >> {low}) & 0x{mask:X})\n"
                        header_content += f"#define {field_name}_SET(x)   (((x) & 0x{mask:X}) << {low})\n"
                    else:
                        # Single bit field
                        bit_pos = int(bits)
                        header_content += f"#define {field_name}_BIT    {bit_pos:>15}\n"
                        header_content += f"#define {field_name}_MASK   0x{1 << bit_pos:08X}\n"
                    
                    header_content += "\n"
        
        # Generate utility functions
        header_content += '''
/* Utility Functions */
static inline uint32_t audio_codec_read_reg(uintptr_t base, uint32_t offset) {
    return *((volatile uint32_t*)(base + offset));
}

static inline void audio_codec_write_reg(uintptr_t base, uint32_t offset, uint32_t value) {
    *((volatile uint32_t*)(base + offset)) = value;
}

/* Helper Macros */
#define AUDIO_CODEC_READ(base, reg)        audio_codec_read_reg(base, reg)
#define AUDIO_CODEC_WRITE(base, reg, val)  audio_codec_write_reg(base, reg, val)

#endif /* {module_name}_REGS_H */
'''
        
        # Write to file
        output_file = self.output_dir / f"{reg_map['module_name']}_regs.h"
        with open(output_file, 'w') as f:
            f.write(header_content)
        
        print(f"Generated C header: {output_file}")
    
    def generate_python_test(self):
        """Generate Python test script"""
        reg_map = self.config["register_map"]
        
        test_content = f'''#!/usr/bin/env python3
"""
Auto-generated Python Test Script for {reg_map["description"]}
Generated from: {self.json_file.name}
Generated on: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}

DO NOT EDIT MANUALLY - This file is auto-generated
"""

import pytest
from typing import Dict, Any

class {reg_map["module_name"].title()}RegisterTest:
    """Test class for {reg_map["description"]}"""
    
    def __init__(self):
        self.registers = {{
'''
        
        # Generate register dictionary
        for reg in reg_map["registers"]:
            test_content += f'            "{reg["name"]}": {{\n'
            test_content += f'                "address": {reg["address"]},\n'
            test_content += f'                "reset_value": {reg["reset_value"]},\n'
            test_content += f'                "access": "{reg["access"]}",\n'
            test_content += f'                "description": "{reg["description"]}"\n'
            test_content += '            },\n'
        
        test_content += '''        }
    
    def test_register_addresses(self):
        """Test that all register addresses are unique"""
        addresses = [reg["address"] for reg in self.registers.values()]
        assert len(addresses) == len(set(addresses)), "Duplicate register addresses found"
    
    def test_reset_values(self):
        """Test register reset values"""
        for name, reg in self.registers.items():
            reset_val = reg["reset_value"]
            # Verify reset value is valid 32-bit value
            assert 0 <= int(reset_val, 16) <= 0xFFFFFFFF, f"Invalid reset value for {name}"
    
    def test_access_permissions(self):
        """Test register access permissions"""
        valid_access = ["RO", "RW", "WO", "RW1C"]
        for name, reg in self.registers.items():
            assert reg["access"] in valid_access, f"Invalid access type for {name}: {reg['access']}"

if __name__ == "__main__":
    test = {reg_map["module_name"].title()}RegisterTest()
    test.test_register_addresses()
    test.test_reset_values()
    test.test_access_permissions()
    print("All register tests passed!")
'''
        
        # Write to file
        output_file = self.output_dir / f"test_{reg_map['module_name']}_regs.py"
        with open(output_file, 'w') as f:
            f.write(test_content)
        
        print(f"Generated Python test: {output_file}")
    
    def generate_documentation(self):
        """Generate Markdown documentation"""
        reg_map = self.config["register_map"]
        
        doc_content = f'''# {reg_map["description"]} Register Map

**Version:** {reg_map["version"]}  
**Generated:** {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}  
**Source:** {self.json_file.name}

## Overview

This document describes the register map for the {reg_map["description"]}.

- **Base Address:** {reg_map["base_address"]}
- **Address Width:** {reg_map["address_width"]} bits
- **Data Width:** {reg_map["data_width"]} bits
- **Addressing:** {"Byte" if reg_map["byte_addressing"] else "Word"}

## Register Summary

| Address | Name | Access | Reset Value | Description |
|---------|------|--------|-------------|-------------|
'''
        
        # Generate register summary table
        for reg in reg_map["registers"]:
            doc_content += f"| {reg['address']} | {reg['name']} | {reg['access']} | {reg['reset_value']} | {reg['description']} |\n"
        
        doc_content += "\n## Register Detailed Descriptions\n\n"
        
        # Generate detailed descriptions
        for reg in reg_map["registers"]:
            doc_content += f"### {reg['name']} - {reg['description']}\n\n"
            doc_content += f"**Address:** {reg['address']}  \n"
            doc_content += f"**Reset Value:** {reg['reset_value']}  \n"
            doc_content += f"**Access:** {reg['access']}  \n\n"
            
            if "fields" in reg and reg["fields"]:
                doc_content += "| Bits | Field Name | Access | Reset | Description |\n"
                doc_content += "|------|------------|--------|-------|-------------|\n"
                
                for field in reg["fields"]:
                    doc_content += f"| {field['bits']} | {field['name']} | {field['access']} | {field['reset_value']} | {field['description']} |\n"
            
            doc_content += "\n"
        
        # Add access type definitions
        doc_content += """## Access Type Definitions

- **RO**: Read Only
- **RW**: Read/Write
- **WO**: Write Only  
- **RW1C**: Read/Write 1 to Clear

## Usage Examples

### C Code Example

```c
#include "audio_codec_regs.h"

// Read version register
uint32_t version = AUDIO_CODEC_READ(base_addr, REG_VERSION);
uint32_t major = REG_VERSION_MAJOR_VER_GET(version);

// Configure sample rate
AUDIO_CODEC_WRITE(base_addr, REG_SAMPLE_RATE, 48000);

// Start encoding
uint32_t ctrl = AUDIO_CODEC_READ(base_addr, REG_CONTROL);
ctrl |= REG_CONTROL_MODE_SET(0x01) | REG_CONTROL_START_MASK;
AUDIO_CODEC_WRITE(base_addr, REG_CONTROL, ctrl);
```

### Python Example

```python
# Register test
from test_audio_codec_regs import AudioCodecRegisterTest

test = AudioCodecRegisterTest()
test.test_register_addresses()
test.test_reset_values()
```
"""
        
        # Write to file
        output_file = self.output_dir / f"{reg_map['module_name']}_register_map.md"
        with open(output_file, 'w') as f:
            f.write(doc_content)
        
        print(f"Generated documentation: {output_file}")

def main():
    """Main function"""
    parser = argparse.ArgumentParser(description="Audio Codec Register Generator")
    parser.add_argument("json_file", help="JSON register map file")
    parser.add_argument("--output-dir", "-o", help="Output directory", default="generated")
    parser.add_argument("--sv-only", action="store_true", help="Generate SystemVerilog only")
    parser.add_argument("--c-only", action="store_true", help="Generate C header only")
    parser.add_argument("--doc-only", action="store_true", help="Generate documentation only")
    
    args = parser.parse_args()
    
    try:
        generator = RegisterGenerator(args.json_file)
        generator.output_dir = Path(args.output_dir)
        generator.output_dir.mkdir(exist_ok=True)
        
        if args.sv_only:
            generator.generate_systemverilog()
        elif args.c_only:
            generator.generate_c_header()
        elif args.doc_only:
            generator.generate_documentation()
        else:
            generator.generate_all()
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main()) 