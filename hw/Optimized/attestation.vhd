-- Author: John Zhu
-- Copyright (c) 2018 University of Maryland Baltimore County
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy 
-- of this software and associated documentation files (the "Software"), to deal 
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
-- copies of the Software, and to permit persons to whom the Software is furnished 
-- to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all 
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
-- INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A 
-- PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT 
-- HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION 
-- OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity attestation is
	generic (
		BLOCK_SIZE     : positive := 128;
		CV_SIZE        : positive := 128;
		SIMON_BPC : positive := 32
	);
	port( 
		clk : in std_logic;
		HEX0 : out std_logic_vector (6 downto 0);
		HEX1 : out std_logic_vector (6 downto 0);
		HEX2 : out std_logic_vector (6 downto 0);
		HEX3 : out std_logic_vector (6 downto 0);
		HEX4 : out std_logic_vector (6 downto 0);
		HEX5 : out std_logic_vector (6 downto 0);
		HPS_DDR3_ADDR : out std_logic_vector(14 downto 0);
		HPS_DDR3_BA : out std_logic_vector(2 downto 0);
		HPS_DDR3_CAS_N : out std_logic;
      HPS_DDR3_CKE : out std_logic;
      HPS_DDR3_CK_N : out std_logic;
		HPS_DDR3_CK_P : out std_logic;
		HPS_DDR3_CS_N : out std_logic;
		HPS_DDR3_DM : out std_logic_vector(3 downto 0);
      HPS_DDR3_DQ : inout std_logic_vector(31 downto 0);
		HPS_DDR3_DQS_N : inout std_logic_vector(3 downto 0);
		HPS_DDR3_DQS_P : inout std_logic_vector(3 downto 0);
      HPS_DDR3_ODT : out std_logic;
		HPS_DDR3_RAS_N : out std_logic;
		HPS_DDR3_RESET_N : out std_logic;
		HPS_DDR3_RZQ : in std_logic;
		HPS_DDR3_WE_N : out std_logic
		
	);
end attestation;

architecture behavior of attestation is

	-- SHA256 Storage
	signal PCR : std_logic_vector(BLOCK_SIZE-1 downto 0);
	signal MSG : std_logic_vector(BLOCK_SIZE-1 downto 0);
	signal DIGEST : std_logic_vector(BLOCK_SIZE-1 downto 0);
		
	-- SIMON Storage
	signal secret_key : unsigned(CV_SIZE-1 downto 0) := X"0f0e0d0c0b0a09080706050403020100";
	signal simon_block : std_logic_vector(BLOCK_SIZE-1 downto 0);
	
	-- HPS Control Signals
	signal hps2fpga_inputs : std_logic_vector(3 downto 0);
	signal rst_in : std_logic;
	signal hash_in : std_logic;
	signal extd_in : std_logic;
	signal quot_in : std_logic;
	signal hps2fpga_outputs : std_logic_vector(3 downto 0);
	signal rst_out : std_logic;
	signal hash_out : std_logic;
	signal extd_out : std_logic;
	signal quot_out : std_logic;
	
	-- HPS Input Signals
	signal reset_n : std_logic;
	signal MSG_0_hps : std_logic_vector(31 downto 0);
	signal MSG_1_hps : std_logic_vector(31 downto 0);
	signal MSG_2_hps : std_logic_vector(31 downto 0);
	signal MSG_3_hps : std_logic_vector(31 downto 0);
	
------------------------ FUNCTIONS -----------------------------------------------------
	
	function log2( i : natural) return integer is
   variable temp    : integer := i;
   variable ret_val : integer := 0; 
   begin					
		while temp > 1 loop
			ret_val := ret_val + 1;
			temp    := temp / 2;     
		end loop;
		return ret_val;
	end log2;
	
------------------------ COMPONENTS -----------------------------------------------------
	
	component hex_display
		port(
			hex_input : in std_logic_vector(3 downto 0);
			hex_output : out std_logic_vector(6 downto 0)
		);
	end component;
	
	component proj is
		port (
			clk_clk             : in    std_logic                     := 'X';             -- clk
			h2f_inputs_in_port  : in    std_logic_vector(3 downto 0)  := (others => 'X'); -- in_port
			h2f_inputs_out_port : out   std_logic_vector(3 downto 0);                     -- out_port
			hash_0_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
			hash_1_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
			hash_2_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
			hash_3_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
			hps_reset_reset_n   : out   std_logic;                                        -- reset_n
			memory_mem_a        : out   std_logic_vector(14 downto 0);                    -- mem_a
			memory_mem_ba       : out   std_logic_vector(2 downto 0);                     -- mem_ba
			memory_mem_ck       : out   std_logic;                                        -- mem_ck
			memory_mem_ck_n     : out   std_logic;                                        -- mem_ck_n
			memory_mem_cke      : out   std_logic;                                        -- mem_cke
			memory_mem_cs_n     : out   std_logic;                                        -- mem_cs_n
			memory_mem_ras_n    : out   std_logic;                                        -- mem_ras_n
			memory_mem_cas_n    : out   std_logic;                                        -- mem_cas_n
			memory_mem_we_n     : out   std_logic;                                        -- mem_we_n
			memory_mem_reset_n  : out   std_logic;                                        -- mem_reset_n
			memory_mem_dq       : inout std_logic_vector(31 downto 0) := (others => 'X'); -- mem_dq
			memory_mem_dqs      : inout std_logic_vector(3 downto 0)  := (others => 'X'); -- mem_dqs
			memory_mem_dqs_n    : inout std_logic_vector(3 downto 0)  := (others => 'X'); -- mem_dqs_n
			memory_mem_odt      : out   std_logic;                                        -- mem_odt
			memory_mem_dm       : out   std_logic_vector(3 downto 0);                     -- mem_dm
			memory_oct_rzqin    : in    std_logic                     := 'X';             -- oct_rzqin
			msg_0_readdata      : out   std_logic_vector(31 downto 0);                    -- readdata
			msg_1_readdata      : out   std_logic_vector(31 downto 0);                    -- readdata
			msg_2_readdata      : out   std_logic_vector(31 downto 0);                    -- readdata
			msg_3_readdata      : out   std_logic_vector(31 downto 0);                    -- readdata
			pcr_0_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
			pcr_1_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
			pcr_2_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
			pcr_3_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
			reset_reset_n       : in    std_logic                     := 'X'              -- reset_n
		);
	end component proj;
	
	component rtsandrtr is
		generic(
			BLOCK_SIZE : positive := 128;
			CV_SIZE : positive := 128;
			SIMON_BPC : positive := 32;
			COUNT_SIZE : positive := 2
		);
		port(
			clk : in std_logic;
			reset_n : in std_logic;
			hps_msg : in std_logic_vector(BLOCK_SIZE-1 downto 0);
			secret_key : in unsigned(CV_SIZE-1 downto 0);
			rst_in  : in std_logic;
			hash_in : in std_logic;
			extd_in : in std_logic;
			quot_in : in std_logic;
			rst_out  : out std_logic;
			hash_out : out std_logic;
			extd_out : out std_logic;
			quot_out : out std_logic;
			DIGEST : out std_logic_vector(BLOCK_SIZE-1 downto 0);
			PCR : out std_logic_vector(BLOCK_SIZE-1 downto 0)
		);
	end component rtsandrtr;
	
	
begin
	rst_in <= hps2fpga_inputs(0);
	hash_in <= hps2fpga_inputs(1);
	extd_in <= hps2fpga_inputs(2);
	quot_in <= hps2fpga_inputs(3);
	hps2fpga_outputs <= quot_out & extd_out & hash_out & rst_out;
	
	hex_d5 : component hex_display
	port map (
			hex_input => PCR(7 downto 4),
			hex_output => HEX5
	);
	hex_d4 : component hex_display
	port map (
			hex_input => PCR(3 downto 0),
			hex_output => HEX4
	);
	hex_d3 : component hex_display
	port map (
			hex_input => PCR(15 downto 12),
			hex_output => HEX3
	);
	hex_d2 : component hex_display
	port map (
			hex_input => PCR(11 downto 8),
			hex_output => HEX2
	);
	hex_d1 : component hex_display
	port map (
			hex_input => PCR(23 downto 20),
			hex_output => HEX1
	);
	hex_d0 : component hex_display
	port map (
			hex_input => PCR(19 downto 16),
			hex_output => HEX0
	);

	unit : component rtsandrtr
	generic map(
		BLOCK_SIZE => BLOCK_SIZE,
		CV_SIZE => CV_SIZE,
		SIMON_BPC => SIMON_BPC,
		COUNT_SIZE => log2(BLOCK_SIZE/SIMON_BPC)
	)
	port map(
		clk => clk,
		reset_n => reset_n,
		hps_msg => MSG_0_hps & MSG_1_hps & MSG_2_hps & MSG_3_hps,
		secret_key => secret_key,
		rst_in => rst_in,
		hash_in => hash_in,
		extd_in => extd_in,
		quot_in => quot_in,
		rst_out => rst_out,
		hash_out => hash_out,
		extd_out => extd_out,
		quot_out => quot_out,
		DIGEST => DIGEST,
		PCR => PCR
	);
	
	interconnects : component proj
	port map (
		clk_clk            => clk,            --        clk.clk
		pcr_3_writedata       => PCR(31 downto 0),
		pcr_2_writedata       => PCR(63 downto 32),
		pcr_1_writedata       => PCR(95 downto 64),
		pcr_0_writedata       => PCR(127 downto 96),
		h2f_inputs_in_port  => hps2fpga_outputs,  
		h2f_inputs_out_port => hps2fpga_inputs, 
		hash_3_writedata      => DIGEST(31 downto 0),
		hash_2_writedata      => DIGEST(63 downto 32),
		hash_1_writedata      => DIGEST(95 downto 64),
		hash_0_writedata      => DIGEST(127 downto 96),
		hps_reset_reset_n  => reset_n,  
		memory_mem_a       => HPS_DDR3_ADDR,       -- memory.mem_a
		memory_mem_ba      => HPS_DDR3_BA,      --       .mem_ba
		memory_mem_ck      => HPS_DDR3_CK_P,      --       .mem_ck
		memory_mem_ck_n    => HPS_DDR3_CK_N,    --       .mem_ck_n
		memory_mem_cke     => HPS_DDR3_CKE,     --       .mem_cke
		memory_mem_cs_n    => HPS_DDR3_CS_N,    --       .mem_cs_n
		memory_mem_ras_n   => HPS_DDR3_RAS_N,   --       .mem_ras_n
		memory_mem_cas_n   => HPS_DDR3_CAS_N,   --       .mem_cas_n
		memory_mem_we_n    => HPS_DDR3_WE_N,    --       .mem_we_n
		memory_mem_reset_n => HPS_DDR3_RESET_N, --       .mem_reset_n
		memory_mem_dq      => HPS_DDR3_DQ,      --       .mem_dq
		memory_mem_dqs     => HPS_DDR3_DQS_P,     --       .mem_dqs
		memory_mem_dqs_n   => HPS_DDR3_DQS_N,   --       .mem_dqs_n
		memory_mem_odt     => HPS_DDR3_ODT,     --       .mem_odt
		memory_mem_dm      => HPS_DDR3_DM,      --       .mem_dm
		memory_oct_rzqin   => HPS_DDR3_RZQ,   --       .oct_rzqin
		msg_0_readdata      => MSG_0_hps,      --      msg_0.readdata
		msg_1_readdata      => MSG_1_hps,      --      msg_1.readdata
		msg_2_readdata      => MSG_2_hps,      --      msg_2.readdata
		msg_3_readdata      => MSG_3_hps,      --      msg_3.readdata
		reset_reset_n      => reset_n       --      reset.reset_n
  );
	
	
end behavior;
