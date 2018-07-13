--Author: John Zhu
--Copyright (c) 2018 University of Maryland Baltimore County
--
--Permission is hereby granted, free of charge, to any person obtaining a copy 
--of this software and associated documentation files (the "Software"), to deal 
--in the Software without restriction, including without limitation the rights
--to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
--copies of the Software, and to permit persons to whom the Software is furnished 
--to do so, subject to the following conditions:
--
--The above copyright notice and this permission notice shall be included in all 
--copies or substantial portions of the Software.
--
--THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
--INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A 
--PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT 
--HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION 
--OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE 
--SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity rts is
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
end;

architecture behavior of rts is

	------------------------------------ Signals ---------------------------------------------------------
	-- Buffer Signals
	signal PCR_buffer : std_logic_vector(255 downto 0);
	signal digest_buffer : std_logic_vector(255 downto 0);
	signal digest_tmp : std_logic_vector(255 downto 0);
	
	-- SHA Core Signals
	signal start_i : std_logic;
	signal end_i : std_logic;
	signal ce_sha : std_logic;
	signal di_req : std_logic;
	signal di_wr : std_logic;
	signal bytes_i : std_logic_vector(1 downto 0);
	signal do_valid : std_logic;
	signal wsha_fpga : std_logic := '0';
	signal fpga_end : std_logic;
	signal sha_sel : std_logic;
	signal wsha_en : std_logic;
	signal wsha_reg_in : std_logic;
	
	-- MUX Signals
	signal sel : std_logic;
	signal MSG_tmp : std_logic_vector(31 downto 0);
	
	-- Counter Signals
	signal en_cnt : std_logic;
	signal rst_cnt : std_logic;
	signal maxed : std_logic;
	signal count : unsigned(3 downto 0);
	
	-- Dflipflop Signals
	signal store_PCR : std_logic;
	signal store_DIG : std_logic;
	
	------------------------------------ Components -------------------------------------------------
	component dflipflop is
		generic (
			SIZE  : positive := 256
		);
		port(
			clk : in std_logic;
			reset_n : in std_logic;
			en	: in	std_logic;
			d_in	: in	std_logic_vector(SIZE-1 downto 0);
			d_out	: out	std_logic_vector(SIZE-1 downto 0)
		);
	end component dflipflop;
	
	component counter_verilog is
	generic(
		SIZE : positive := 4
	);
	port(
		clk : in std_logic;
		rst : in std_logic;
		en : in std_logic;
		count : out unsigned(SIZE-1 downto 0)
	);
	end component counter_verilog;
	
	component mux_alt is
	port(
		data0x : in std_logic_vector(31 downto 0);
		data1x : in std_logic_vector(511 downto 0);
		sel : in std_logic;
		step : in unsigned (3 downto 0);
		result : out std_logic_vector(31 downto 0)
	);
	end component mux_alt;
	
	component gv_sha256 is
		port (
			-- clock and core enable
			clk_i : in std_logic := 'U';                                    -- system clock
			ce_i : in std_logic := 'U';                                     -- core clock enable
			-- input data
			di_i : in std_logic_vector (31 downto 0) := (others => 'U');    -- big endian input message words
			bytes_i : in std_logic_vector (1 downto 0) := (others => 'U');  -- valid bytes in input word
			-- start/end commands
			start_i : in std_logic := 'U';                                  -- reset the engine and start a new hash
			end_i : in std_logic := 'U';                                    -- marks end of last block data input
			-- handshake
			di_req_o : out std_logic;                                       -- requests data input for next word
			di_wr_i : in std_logic := 'U';                                  -- high for di_i valid, low for hold
			error_o : out std_logic;                                        -- signalizes error. output data is invalid
			do_valid_o : out std_logic;                                     -- when high, the output is valid
			-- 256bit output registers
			H0_o : out std_logic_vector (31 downto 0);
			H1_o : out std_logic_vector (31 downto 0);
			H2_o : out std_logic_vector (31 downto 0);
			H3_o : out std_logic_vector (31 downto 0);
			H4_o : out std_logic_vector (31 downto 0);
			H5_o : out std_logic_vector (31 downto 0);
			H6_o : out std_logic_vector (31 downto 0);
			H7_o : out std_logic_vector (31 downto 0);
			wsha : in std_logic;
		   step : in unsigned(3 downto 0)
    );                      
	end component gv_sha256;
	

	

------------------------------------ States -----------------------------------------------

	type state_type is (idle,load_hash_p1,load_hash_p2,wait_hash,extend_p1,extend_p2,
	overwrite_p1,overwrite_p2,pause,quote_p1, quote_fdmsg_p1, quote_fdmsg_p2,quote_p2,quote_p3);
   signal state, next_state: state_type;
	
begin
	PCR <= PCR_buffer;
	digest <= digest_buffer;

	DIG_reg : component dflipflop
	generic map (
		SIZE => 256
	)
	port map (
		clk => clk,
		reset_n => reset_n,
		en => store_DIG,
		d_in => digest_tmp,
		d_out => digest_buffer
	);	
	
	PCR_reg : component dflipflop
	generic map (
		SIZE => 256
	)
	port map (
		clk => clk,
		reset_n => reset_n,
		en => store_PCR,
		d_in => digest_tmp,
		d_out => PCR_buffer
	);	
	
	Count_unit : component counter_verilog
	generic map (
		SIZE => 4
	)
	port map (
		clk => clk,
		rst => rst_cnt,
		en => en_cnt,
		count => count
	);
	
	mux_alt_unit : component mux_alt
	port map(
		data0x => hps_msg,
		data1x => PCR_buffer & digest_buffer,
		sel => sel,
		step => count,
		result => MSG_tmp
	);

	sha_core : component gv_sha256
	port map(
	  clk_i => clk,
	  ce_i => ce_sha,
	  di_i => MSG_tmp,    -- big endian input message words
	  bytes_i => bytes_i,  -- valid bytes in input word
	  -- start/end commands
	  start_i => start_i,                                  -- reset the engine and start a new hash
	  end_i => end_i,                                    -- marks end of last block data input
	  -- handshake
	  di_req_o => di_req,                                       -- requests data input for next word
	  di_wr_i => di_wr,                                  -- high for di_i valid, low for hold
	  error_o => open,                                        -- signalizes error. output data is invalid
	  do_valid_o => do_valid,                                     -- when high, the output is valid
	  -- 256bit output registers
	  H0_o => digest_tmp(255 downto 224),
	  H1_o => digest_tmp(223 downto 192),
	  H2_o => digest_tmp(191 downto 160),
	  H3_o => digest_tmp(159 downto 128),
	  H4_o => digest_tmp(127 downto 96),
	  H5_o => digest_tmp(95 downto 64),
	  H6_o => digest_tmp(63 downto 32),
	  H7_o => digest_tmp(31 downto 0),
	  wsha => wsha_fpga,
	  step => count
	);
	
	wsha_reg : process(clk, reset_n)
	begin
		if reset_n = '0' then
			wsha_fpga <= '0';  
		elsif rising_edge(clk) then
			if wsha_en = '1' then
				wsha_fpga <= wsha_reg_in;
			end if;
		end if;  
	end process wsha_reg;
	
	statemachine1 : process(clk,reset_n)
	begin  
		if reset_n = '0' then
			state <= idle;  
		elsif rising_edge(clk) then
			state <= next_state;     
		end if;  
	end process statemachine1;
	
	statemachine2 : process(state, hash_in, extd_in, wsha_in, msgfd_in, msgend_in, quot_in, do_valid)
	begin
		next_state <= state;
		-- Control Signals
		hash_out <= '0';
		extd_out <= '0';
		wsha_out <= '0';
		msgfd_out <= '0';
		msgend_out <= '0';
		-- Counter Signals
		en_cnt <= '0';
		rst_cnt <= '0';
		-- MUX Signals
		sel <= '0';
		-- Fl ipFlop
		store_PCR <= '0';
		store_DIG <= '0';
		-- SHA Signals
		start_i <= '0';
		fpga_end <= '0';
		ce_sha <= '0';
		di_wr <= '0';
		wsha_reg_in <= '0';
		wsha_en <= '0';
		end_i <= '0';
		bytes_i <= B"00";
		-- Quote Signals
		quot_done <= '0';
		case state is
			when idle =>
				if extd_in = '1' then
					ce_sha <= '1';
					sel <= '1';
					extd_out <= '1';
					start_i <= '1';
					next_state <= extend_p1;
				elsif hash_in = '1' then
--					rst_cnt <= '1';
					ce_sha <= '1';
					start_i <= '1';
					next_state <= load_hash_p1;
					hash_out <= '1';
					bytes_i <= bytes_in;
				elsif wsha_in = '1' then
					wsha_reg_in <= '1';
					wsha_en <= '1';
					wsha_out <= '1';
					rst_cnt <= '1';
					next_state <= overwrite_p1;
				elsif quot_in = '1' then
					ce_sha <= '1';
					sel <= '1';
					rst_cnt <= '1';
					start_i <= '1';
					next_state <= quote_p1;
				end if;
			-- Loads in message from host
			when load_hash_p1 =>
				ce_sha <= '1';
				hash_out <= '1';
				bytes_i <= bytes_in;
				next_state <= load_hash_p1;
				if di_req = '1' then
					if msgfd_in = '1' then
						di_wr <= '1';
						en_cnt <= '1';
						if msgend_in = '1' or count = B"111" then
							end_i <= '1';
							next_state <= wait_hash;
						else
							next_state <= load_hash_p2;
						end if;
					end if;
				end if;
			-- Waits for next block
			when load_hash_p2 => 
				ce_sha <= '1';
				msgfd_out <= '1';
				hash_out <= '1';
				if msgfd_in = '0' then
					next_state <= load_hash_p1;
				else
					next_state <= load_hash_p2;
				end if;
			-- Waits till hash is done
			when wait_hash =>
				ce_sha <= '1';
				hash_out <= '1';
				if do_valid = '1' then
					wsha_en <= '1';
					hash_out <= '0';
					store_DIG <= '1';
					rst_cnt <= '1';
					next_state <= pause;
				else
					next_state <= wait_hash;
				end if;
			-- Feeds in PCR || Digest
			when extend_p1 =>
				ce_sha <= '1';
				sel <= '1';
				extd_out <= '1';
				next_state <= extend_p1;
				if di_req = '1' then
					di_wr <= '1';
					en_cnt <= '1';
					if count = X"F" then
						end_i <= '1';
						next_state <= extend_p2;
					end if;
				end if;
			-- Waits for hash to be done
			when extend_p2 =>
				ce_sha <= '1';
				sel <= '1';
				extd_out <= '1';
				if do_valid = '1' then
					store_PCR <= '1';
					next_state <= pause;
				else
					next_state <= extend_p2;
				end if;
			-- Waits for all control signals to be deasserted
			when pause =>
				if msgfd_in = '0' and msgend_in = '0' and hash_in = '0' and wsha_in = '0' and extd_in = '0' then
					next_state <= idle;
				else
					next_state <= pause;
				end if;
			-- Writes in 32-bits into digest
			when overwrite_p1 =>
				if wsha_in = '1' then
					en_cnt <= '1';
					wsha_out <= '1';
					next_state <= overwrite_p2;
				else 
					next_state <= overwrite_p1;
				end if;
			-- Waits for next 32-bit block. If done 8 times, exits
			when overwrite_p2 =>
				if count = X"8" then
					rst_cnt <= '1';
					next_state <= pause;
				elsif wsha_in = '0' then
					next_state <= overwrite_p1;
				else 
					next_state <= overwrite_p2;
				end if;
			-- Feeds PCR to SHA256
			when quote_p1 =>
				ce_sha <= '1'; 
				sel <= '1';
				next_state <= quote_p1;
				if di_req = '1' then
					di_wr <= '1';
					en_cnt <= '1';
					-- Feeds in PCR
					if count = X"7" then
						rst_cnt <= '1';
						next_state <= quote_fdmsg_p1;
					end if;
				end if;
			-- Feeds in Nonce, provided by Host, to SHA256
			when quote_fdmsg_p1 =>
				ce_sha <= '1';
				if msgfd_in = '1' then
					di_wr <= '1';
					en_cnt <= '1';
					if count = X"3" then
						end_i <= '1';
						next_state <= quote_p2;
					else
						next_state <= quote_fdmsg_p2;
					end if;
				else
					next_state <= quote_fdmsg_p1;
				end if;
			-- Waits for next 32-bit block
			when quote_fdmsg_p2 => 
				ce_sha <= '1';
				if msgfd_in = '0' then
					next_state <= quote_fdmsg_p1;
				else
					next_state <= quote_fdmsg_p2;
				end if;
			-- Waits for hash to be done
			when quote_p2 =>
				ce_sha <= '1';
				if do_valid = '1' then
					rst_cnt <= '1';
					store_DIG <= '1';
					next_state <= quote_p3;
				else
					next_state <= quote_p2;
				end if;
			-- Waits till quote operation is done
			when quote_p3 =>
				quot_done <= '1';
				if quot_in = '0' then
					next_state <= idle;
				else
					next_state <= quote_p3;
				end if;
			when others =>
				next_state <= idle;
		end case;
	end process; 


end behavior;
