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

entity rtsandrtr is
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
		rst_out  : out std_logic := '0';
		hash_out : out std_logic := '0';
		extd_out : out std_logic := '0';
		quot_out : out std_logic := '0';
		DIGEST : out std_logic_vector(BLOCK_SIZE-1 downto 0);
		PCR : out std_logic_vector(BLOCK_SIZE-1 downto 0)
	);
end;

architecture behavior of rtsandrtr is
	------------------------------------ Signals ---------------------------------------------------------
	-- PCR
	signal PCR_reg : unsigned(BLOCK_SIZE-1 downto 0) := (others => '0');
	signal en_PCR : std_logic;
	
	-- H_block
	signal H_block : unsigned(BLOCK_SIZE-1 downto 0);
	signal en_blk : std_logic;
	signal rst_blk : std_logic;

	-- Counter Signals
	signal rst_cnt : std_logic;
	signal en_cnt : std_logic;
	signal count : unsigned(COUNT_SIZE-1 downto 0);
	
	-- MUX Datain Signals
	signal sel_din : std_logic := '0';
	
	-- MUX CVin Signals
	signal sel_cv : std_logic_vector(1 downto 0) := B"00";
	
	-- Xor Unit
	signal xor_input : unsigned(SIMON_BPC-1 downto 0);
	
	-- Out Signals
	signal rst_lock : std_logic := '0';
	signal hash_lock : std_logic := '0';
	signal extd_lock : std_logic := '0';
	signal quot_lock : std_logic := '0';
	
	-- Lock Signal
	signal lock_sig : std_logic;
	signal lock_rst : std_logic;
	
	-- SIMON Signals
	signal load : std_logic;
	signal load_CV : std_logic;
	signal done_simon : std_logic;
	signal simon_dout : unsigned(SIMON_BPC-1 downto 0);
	signal simon_din : unsigned(SIMON_BPC-1 downto 0);
	signal simon_CVin : unsigned(SIMON_BPC-1 downto 0);

	------------------------------------ Components ---------------------------------------------------------

	component dflipflop_alt is
	generic (
		IN_SIZE : positive := SIMON_BPC;
		OUT_SIZE : positive := BLOCK_SIZE;
		STEP_SIZE : positive := COUNT_SIZE
	);
	port(
		clk : in std_logic;
		reset : in std_logic;
		en	: in	std_logic;
		d_in	: in	unsigned(IN_SIZE-1 downto 0);
		xor_in : in unsigned(IN_SIZE-1 downto 0);
		d_out	: out	unsigned(OUT_SIZE-1 downto 0);
		step : in unsigned(STEP_SIZE-1 downto 0)
	);
	end component dflipflop_alt;
	
	component counter_verilog is
	generic(
		SIZE : positive := COUNT_SIZE
	);
	port(
		clk : in std_logic;
		rst : in std_logic;
		en : in std_logic;
		count : out unsigned(SIZE-1 downto 0)
	);
	end component counter_verilog;
	
	component mux_simon is 
	generic(
		BLOCK_SIZE : positive := 128;
		SIMON_BPC : positive := 32;
		STEP_SIZE : positive := 2
	);
	port(
		data0x	: in	unsigned(BLOCK_SIZE-1 downto 0); -- H_block
		data1x	: in	unsigned(BLOCK_SIZE-1 downto 0); -- PCR
		data2x	: in	unsigned(BLOCK_SIZE-1 downto 0); -- Key
		data3x	: in	unsigned(BLOCK_SIZE-1 downto 0); -- MSG
		sel_din  : in  std_logic;
		sel_CV   : in	std_logic_vector(1 downto 0);
		step : in unsigned(STEP_SIZE-1 downto 0);
		result_din	: out	unsigned(SIMON_BPC-1 downto 0);
		result_CVin	: out	unsigned(SIMON_BPC-1 downto 0)
	);
	end component mux_simon;
	
	component simon_top is
		generic (
			BLOCK_SIZE     : positive := BLOCK_SIZE;
			CV_SIZE        : positive := CV_SIZE;
			BITS_PER_CYCLE : positive := SIMON_BPC);
		port(
			Clock     : in  std_logic;
			DataIn    : in  unsigned(BITS_PER_CYCLE-1 downto 0);
			Load      : in  std_logic;
			LoadCV    : in  std_logic;
			Done      : out std_logic;
			CryptoVar : in  unsigned(BITS_PER_CYCLE-1 downto 0);
			DataOut   : out unsigned(BITS_PER_CYCLE-1 downto 0)
		 );
	end component;
	
	------------------------------------ States -----------------------------------------------

	type state_type is (idle,encr_p1,encr_p2,quot_p1,quot_p2,store_result,store_Hquot,pause);
   signal state, next_state: state_type;
	
begin
	DIGEST <= std_logic_vector(H_block);
	PCR <= std_logic_vector(PCR_reg);
	rst_out <= rst_lock;
	hash_out <= hash_lock;
	extd_out <= extd_lock;
	quot_out <= quot_lock;
	
	H_unit : component dflipflop_alt
	generic map (
		IN_SIZE => SIMON_BPC,
		OUT_SIZE => BLOCK_SIZE,
		STEP_SIZE => COUNT_SIZE
	)
	port map (
		clk => clk,
		reset => not(reset_n) or rst_blk,
		en => en_blk,
		step => count,
		d_in => simon_dout,
		xor_in => simon_din,
		d_out => H_block
	);	
	
	PCR_unit : component dflipflop_alt
	generic map (
		IN_SIZE => SIMON_BPC,
		OUT_SIZE => BLOCK_SIZE,
		STEP_SIZE => COUNT_SIZE
	)
	port map (
		clk => clk,
		reset => not(reset_n),
		en => en_PCR,
		step => count,
		d_in => simon_dout,
		xor_in => simon_din,
		d_out => PCR_reg
	);	
	
	count_unit : component counter_verilog
	generic map(
		SIZE => COUNT_SIZE
	)
	port map (
		clk => clk,
		rst => rst_cnt,
		en => en_cnt,
		count => count
	);
	
	mux_unit : component mux_simon  
	generic map(
		BLOCK_SIZE => BLOCK_SIZE,
		SIMON_BPC => SIMON_BPC,
		STEP_SIZE => COUNT_SIZE
	)
	port map(
		data0x => H_block,
		data1x => PCR_reg,
		data2x => secret_key,
		data3x => unsigned(hps_msg),
		sel_din => sel_din,
		sel_CV => sel_CV,
		step => count,
		result_din => simon_din,
		result_CVin	=> simon_CVin
	);
	
	simon_comp : simon_top
	generic map ( 
		BLOCK_SIZE => BLOCK_SIZE,
		CV_SIZE => CV_SIZE,
		BITS_PER_CYCLE => SIMON_BPC
	)
	port map(
		Clock => clk,
		DataIn => simon_din,
		Load => load,   
		LoadCV => load_CV,
		Done => done_simon,
		CryptoVar => simon_CVin,
		DataOut => simon_dout
	);
	-- Locks the control signals after idle state has been changed.
	-- Prevents unintentional bit flipping. Not necessarily a security measure
	ctrl_lock : process(lock_sig)
	begin
		if rising_edge(clk) then
			if lock_rst = '1' then 
				rst_lock <= '0';
				hash_lock <= '0';
				quot_lock <= '0';
				extd_lock <= '0';
			elsif lock_sig = '1' then
				rst_lock <= rst_in;
				hash_lock <= hash_in;
				quot_lock <= quot_in;
				extd_lock <= extd_in;
			end if;
		end if;
	end process ctrl_lock;
	
	statemachine1 : process(clk,reset_n)
	begin  
		if reset_n = '0' then
			state <= idle;  
		elsif rising_edge(clk) then
			state <= next_state;     
		end if;  
	end process statemachine1;
	
	statemachine2 : process(state,rst_lock,hash_lock,extd_lock,quot_lock,done_simon)
	begin  
		next_state <= state;
		-- Lock Signals
		lock_rst <= '0';
		lock_sig <= '0';
		-- MUX Signals
		sel_din <= '0';
		sel_cv <= B"00";
		-- Counter signals
		en_cnt <= '0';
		rst_cnt <= '0';
		-- SIMON block signals
		en_blk <= '0';
		rst_blk <= '0';
		-- SIMON signals
		load <= '0';
		load_CV <= '0';
		-- PCR signal
		en_PCR <= '0';
		case state is
			when idle =>
				lock_sig <= '1';
				if rst_lock = '1' then
					rst_blk <= '1';
					next_state <= pause;
				end if;
				if hash_lock = '1' then
					sel_din <= '0';
					sel_cv <= B"00";
					next_state <= encr_p1;
				elsif extd_lock = '1' then
					sel_din <= '1';
					sel_cv <= B"01";
					next_state <= encr_p1;
				elsif quot_lock = '1' then
					sel_din <= '1';
					sel_cv <= B"00";
					next_state <= quot_p1;
				end if;
			-- Encrypts the necessary plaintext and cryptovariable for each operation
			when encr_p1 =>
				if hash_lock = '1' then
					sel_din <= '0';
					sel_cv <= B"00";
				elsif extd_lock = '1' then
					sel_din <= '1';
					sel_cv <= B"01";
				elsif quot_lock = '1' then
					sel_din <= '0';
					sel_cv <= B"10";
				end if;
				en_cnt <= '1';
				load <= '1';
				load_CV <= '1';
				if count = B"11" then
					if quot_lock = '1' then
						rst_blk <= '1';
					end if;
					next_state <= encr_p2;
				else
					next_state <= encr_p1;
				end if;
			-- Waits till encryption is done
			when encr_p2 =>
				if hash_lock = '1' then
					sel_din <= '0';
				elsif extd_lock = '1' then
					sel_din <= '1';
				elsif quot_lock = '1' then
					sel_din <= '0';
				end if;
				if done_simon = '1' then
					en_cnt <= '1';
					next_state <= store_result;
					-- If we are doing an EXTEND, we want to write into PCR.
					-- Otherwise, write into block
					if extd_lock = '1' then
						en_PCR <= '1';
					else
						en_blk <= '1';
					end if;
				else
					next_state <= encr_p2;
				end if;
			-- Stores result of encryption or hash to the necessary block
			when store_result =>
				if hash_lock = '1' then
					en_blk <= '1';
					sel_din <= '0';
				elsif extd_lock = '1' then
					en_PCR <= '1';
					sel_din <= '1';
				elsif quot_lock = '1' then
					en_blk <= '1';
					sel_din <= '0';
				end if;
				en_cnt <= '1';
				if count = B"11" then
					next_state <= pause;
				else
					next_state <= store_result;
				end if;
			-- Quote operations require a hash and then an encrypt
			-- The hash of PCR||Nonce is done in quot_p1. The encrypt is done in encr_p1 and so on.
			-- Hashes the PCR and Nonce, where Nonce is provided by hps_msg
			when quot_p1 =>
				sel_din <= '1';
				sel_cv <= B"00";
				en_cnt <= '1';
				load <= '1';
				load_CV <= '1';
				if count = B"11" then
					next_state <= quot_p2;
				else
					next_state <= quot_p1;
				end if;
			-- Waits till hash operation is done
			when quot_p2 =>
				sel_din <= '1';
				if done_simon = '1' then
					en_cnt <= '1';
					en_blk <= '1';
					next_state <= store_Hquot;
				else
					next_state <= quot_p2;
				end if;
			-- XORes result with PCR, and stores it in Regblk. Goes to encr_p1 to encrypt signature
			when store_Hquot =>
				sel_din <= '1';
				en_cnt <= '1';
				en_blk <= '1';
				if count = B"11" then
					next_state <= encr_p1;
				else
					next_state <= store_Hquot;
				end if;
			-- Waits till all control signals are deasserted
			when pause =>
				lock_rst <= '1';
				if rst_in = '0' and hash_in = '0' and extd_in = '0' and quot_in = '0' then
					next_state <= idle;
				else
					next_state <= pause;
				end if;
		end case;
	end process statemachine2;

end behavior;
