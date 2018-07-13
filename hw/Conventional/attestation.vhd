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

library avs_aes_lib;
use avs_aes_lib.avs_aes_pkg.all;

entity attestation is
	generic (
		BLOCK_SIZE     : positive := 128;
		CV_SIZE        : positive := 256;
		BITS_PER_CLK : positive := 32
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
	signal PCR : std_logic_vector(255 downto 0);
	signal MSG : std_logic_vector(511 downto 0);
	signal MSG_comb : std_logic_vector(511 downto 0);
	signal DIGEST : std_logic_vector(255 downto 0);
	
	-- SHA256 Control Signals
	signal rtr_quot_in : std_logic;
	signal rtr_quot_done : std_logic;
	
	-- AES Registers
	signal secret_key : DWORDARRAY (0 to 7) := (
		0 => X"00010203", 1 => X"04050607",
		2 => X"08090a0b", 3 => X"0c0d0e0f",
		4 => X"10111213", 5 => X"14151617",
		6 => X"18191a1b", 7 => X"1c1d1e1f"
		);
	signal aes_block : std_logic_vector(127 downto 0);
	
	-- RTR Signals
	signal Regblk : std_logic_vector(BLOCK_SIZE-1 downto 0);
	-- HPS Control Signals
	signal hps2fpga_inputs : std_logic_vector(9 downto 0);
	signal msgfd_in : std_logic;
	signal msgend_in : std_logic;
	signal bytes_in : std_logic_vector(1 downto 0);
	signal hash_in : std_logic;
	signal extd_in : std_logic;
	signal wsha_in : std_logic;
	signal encr_in : std_logic;
	signal decr_in : std_logic;
	signal quot_in : std_logic;

	signal hps2fpga_outputs : std_logic_vector(9 downto 0);
	signal msgfd_out : std_logic;
	signal msgend_out : std_logic;
	signal hash_out : std_logic;
	signal extd_out : std_logic;
	signal wsha_out : std_logic;
	signal quot_out : std_logic;
	signal encr_out : std_logic;
	signal decr_out : std_logic;
	
	-- HPS Input Signals
	signal reset_n : std_logic;
	signal MSG_0_hps : std_logic_vector(31 downto 0);

	-- States
	type state_type is (idle, extending, quoting);--, quote_p1, quote_p2, hash_done);
   signal state, next_state: state_type;
	
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
            h2f_inputs_in_port  : in    std_logic_vector(9 downto 0)  := (others => 'X'); -- in_port
            h2f_inputs_out_port : out   std_logic_vector(9 downto 0);                     -- out_port
            hash_0_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            hash_1_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            hash_2_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            hash_3_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            hash_4_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            hash_5_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            hash_6_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            hash_7_writedata    : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
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
            pcr_0_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            pcr_1_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            pcr_2_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            pcr_3_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            pcr_4_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            pcr_5_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            pcr_6_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            pcr_7_writedata     : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
				block_0_writedata   : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            block_1_writedata   : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            block_2_writedata   : in    std_logic_vector(31 downto 0) := (others => 'X'); -- writedata
            block_3_writedata   : in    std_logic_vector(31 downto 0) := (others => 'X');  -- writedata
            reset_reset_n       : in    std_logic                     := 'X'              -- reset_n
        );
    end component proj;
	
	component rts is
		port(
			clk : in std_logic;
			reset_n : in std_logic;
			msgfd_in : in std_logic;
			msgend_in : in std_logic;
			bytes_in : in std_logic_vector(1 downto 0);
			wsha_in : in std_logic;
			hash_in : in std_logic;
			extd_in : in std_logic;
			quot_in : in std_logic;
			msgfd_out : out std_logic;
			msgend_out : out std_logic;
			hash_out : out std_logic;
			extd_out : out std_logic;
			wsha_out : out std_logic;
			quot_done : out std_logic;
			hps_msg : in std_logic_vector(31 downto 0);
			digest  : out std_logic_vector(255 downto 0);
			PCR : out std_logic_vector(255 downto 0)
		);
	end component rts;
	
	component rtr is
		generic(
			BLOCK_SIZE : positive := BLOCK_SIZE;
			CV_SIZE : positive := CV_SIZE;
			BITS_PER_CLK : positive := BITS_PER_CLK;
			COUNT_SIZE : positive := 3
		);
		port(
			clk : in std_logic;
			reset_n : in std_logic;
			hps_msg : in DWORD;
			quote_msg : in std_logic_vector(BLOCK_SIZE-1 downto 0);
			quote_sha : out std_logic;
			quote_sha_done : in std_logic;
			secret_key : in DWORDARRAY (0 to 7);
			encr_in : in std_logic;
			decr_in : in std_logic;
			quot_in : in std_logic;
			encr_out : out std_logic;
			decr_out : out std_logic;
			quot_out : out std_logic;
			block_out : out std_logic_vector(BLOCK_SIZE-1 downto 0)
		);
	end component rtr;
	
begin	
-- Assign each control signal a name for easier programming
	msgfd_in <= hps2fpga_inputs(0);
	msgend_in <= hps2fpga_inputs(1);
	bytes_in <= hps2fpga_inputs(3 downto 2);
	wsha_in <= hps2fpga_inputs(4);
	hash_in <= hps2fpga_inputs(5);
	extd_in <= hps2fpga_inputs(6);
	encr_in <= hps2fpga_inputs(7);
	decr_in <= hps2fpga_inputs(8);
	quot_in <= hps2fpga_inputs(9);
	hps2fpga_outputs <= quot_out & decr_out & encr_out & extd_out & hash_out & wsha_out & bytes_in & msgend_out & msgfd_out;
	
	hex_d5 : component hex_display
	port map (
			hex_input => PCR(255 downto 252),
			hex_output => HEX5
	);
	hex_d4 : component hex_display
	port map (
			hex_input => PCR(251 downto 248),
			hex_output => HEX4
	);
	hex_d3 : component hex_display
	port map (
			hex_input => PCR(247 downto 244),
			hex_output => HEX3
	);
	hex_d2 : component hex_display
	port map (
			hex_input => PCR(243 downto 240),
			hex_output => HEX2
	);
	hex_d1 : component hex_display
	port map (
			hex_input => PCR(239 downto 236),
			hex_output => HEX1
	);
	hex_d0 : component hex_display
	port map (
			hex_input => PCR(235 downto 232),
			hex_output => HEX0
	);

	rts_entity : component rts
	port map(
		clk => clk,
		reset_n => reset_n,
		hps_msg => MSG_0_hps(7 downto 0) & MSG_0_hps(15 downto 8) & MSG_0_hps(23 downto 16) & MSG_0_hps(31 downto 24),
		msgfd_in => msgfd_in,
		msgend_in => msgend_in,
		bytes_in => bytes_in,
		hash_in => hash_in,
		extd_in => extd_in,
		wsha_in => wsha_in,
		msgfd_out => msgfd_out,
		msgend_out => msgend_out,
		hash_out => hash_out,
		wsha_out => wsha_out,
		extd_out => extd_out,
		quot_in => rtr_quot_in,
		quot_done => rtr_quot_done,
		digest => DIGEST,
		PCR => PCR
	);
	
	rtr_entity : component rtr
		generic map(
			BLOCK_SIZE => BLOCK_SIZE,
			CV_SIZE => CV_SIZE,
			BITS_PER_CLK => BITS_PER_CLK,
			COUNT_SIZE => 3
		)
		port map(
			clk => clk,
			reset_n => reset_n,
			hps_msg => MSG_0_hps(7 downto 0) & MSG_0_hps(15 downto 8) & MSG_0_hps(23 downto 16) & MSG_0_hps(31 downto 24),
			quote_msg => DIGEST(255 downto 128),
			quote_sha => rtr_quot_in,
			quote_sha_done => rtr_quot_done,
			secret_key => secret_key,
			encr_in => encr_in,
			decr_in => decr_in,
			quot_in => quot_in,
			decr_out => decr_out,
			encr_out => encr_out,
			quot_out => quot_out,
			block_out => Regblk
	);
	

	interconnects : component proj
	port map (
			pcr_0_writedata       => PCR(7 downto 0) & PCR(15 downto 8) &
										 PCR(23 downto 16) & PCR(31 downto 24),       
			pcr_1_writedata       => PCR(39 downto 32) & PCR(47 downto 40) &
										 PCR(55 downto 48) & PCR(63 downto 56),       
			pcr_2_writedata       => PCR(71 downto 64) & PCR(79 downto 72) &
										 PCR(87 downto 80) & PCR(95 downto 88),       
			clk_clk            => clk,            --        clk.clk
			pcr_3_writedata       => PCR(103 downto 96) & PCR(111 downto 104) &
										 PCR(119 downto 112) & PCR(127 downto 120),       
			pcr_4_writedata       => PCR(135 downto 128) & PCR(143 downto 136) &
										 PCR(151 downto 144) & PCR(159 downto 152),      
			pcr_5_writedata       => PCR(167 downto 160) & PCR(175 downto 168) &
										 PCR(183 downto 176) & PCR(191 downto 184),       
			pcr_6_writedata       => PCR(199 downto 192) & PCR(207 downto 200) &
										 PCR(215 downto 208) & PCR(223 downto 216),       
			pcr_7_writedata       => PCR(231 downto 224) & PCR(239 downto 232) &
										 PCR(247 downto 240) & PCR(255 downto 248),     
			h2f_inputs_in_port => hps2fpga_outputs, 
			h2f_inputs_out_port => hps2fpga_inputs, 
			
			hash_0_writedata      => DIGEST(7 downto 0) & DIGEST(15 downto 8) &
										 DIGEST(23 downto 16) & DIGEST(31 downto 24),     
			hash_1_writedata      => DIGEST(39 downto 32) & DIGEST(47 downto 40) &
										 DIGEST(55 downto 48) & DIGEST(63 downto 56),      
			hash_2_writedata      => DIGEST(71 downto 64) & DIGEST(79 downto 72) &
										 DIGEST(87 downto 80) & DIGEST(95 downto 88),      
			hash_3_writedata      => DIGEST(103 downto 96) & DIGEST(111 downto 104) &
										 DIGEST(119 downto 112) & DIGEST(127 downto 120),     
			hash_4_writedata      => DIGEST(135 downto 128) & DIGEST(143 downto 136) &
										 DIGEST(151 downto 144) & DIGEST(159 downto 152),     
			hash_5_writedata      => DIGEST(167 downto 160) & DIGEST(175 downto 168) &
										 DIGEST(183 downto 176) & DIGEST(191 downto 184),     
			hash_6_writedata      => DIGEST(199 downto 192) & DIGEST(207 downto 200) &
										 DIGEST(215 downto 208) & DIGEST(223 downto 216),      
			hash_7_writedata      => DIGEST(231 downto 224) & DIGEST(239 downto 232) &
										 DIGEST(247 downto 240) & DIGEST(255 downto 248),   
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
			block_3_writedata   => Regblk(103 downto 96) & Regblk(111 downto 104) & 
											Regblk(119 downto 112) & Regblk(127 downto 120),
			block_2_writedata   => Regblk(71 downto 64) & Regblk(79 downto 72) 
											& Regblk(87 downto 80) & Regblk(95 downto 88),
			block_1_writedata   => Regblk(39 downto 32) & Regblk(47 downto 40) 
											& Regblk(55 downto 48) & Regblk(63 downto 56),
			block_0_writedata   => Regblk(7 downto 0) & Regblk(15 downto 8) 
											& Regblk(23 downto 16) & Regblk(31 downto 24),
			reset_reset_n      => reset_n    
  );
	
	
end behavior;
