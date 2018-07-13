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

--library avs_aes_lib;
use work.avs_aes_pkg.all;

entity rtr is
	generic(
		BLOCK_SIZE : positive := 128;
		CV_SIZE : positive := 256;
		BITS_PER_CLK : positive := 32;
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
end;

architecture behavior of rtr is
	
	------------------------------------ Signals ----------------------------------------------------
	-- Counter Signals
	signal rst_cnt : std_logic;
	signal en_cnt : std_logic;
	signal count : unsigned(COUNT_SIZE-1 downto 0) := (others => '0');
	
	-- Block Signals
	signal Regblk : STATE;
	signal store_res : std_logic;
	signal quot_write : std_logic;
	signal hps_write : std_logic;
	signal rst_blk : std_logic;
	signal en_blk : std_logic;
	
	-- Signals interfacing the AES core
	signal decrypt_mode : STD_LOGIC;
	signal data_stable : STD_LOGIC;	 -- input data is valid --> process it
	signal w_ena_keyword : STD_LOGIC;	-- write enable of keyword to wordaddr
	signal key_stable	 : STD_LOGIC;  -- key is complete and valid, start expansion
	signal result : STATE;		-- output
	signal keyexp_done : std_logic;
	signal finished : STD_LOGIC;	-- output valid
	
	------------------------------------ Components -------------------------------------------------
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
	
	component AES_CORE is
	generic (
		KEYLENGTH  : NATURAL := CV_SIZE;  -- Size of keyblock (128, 192, 256 Bits)
		DECRYPTION : BOOLEAN := true	-- include decrypt datapath
		);
	port(
		clk			  : in	STD_LOGIC;	-- system clock
		data_in		  : in	STATE;		-- payload to encrypt
		data_stable	  : in	STD_LOGIC;	-- flag valid payload
		keyword		  : in	DWORD;		-- word of original userkey
		keywordaddr	  : in	STD_LOGIC_VECTOR(2 downto 0);  -- keyword register address
		w_ena_keyword : in	STD_LOGIC;	-- write enable of keyword to wordaddr
		key_stable	  : in	STD_LOGIC;	-- key is complete and valid, start expansion
		decrypt_mode  : in	STD_LOGIC;	-- decrypt='1',encrypt='0'
		keyexp_done	  : out  STD_LOGIC;	-- keyprocessing is done
		result		  : out  STATE;		-- output
		finished	  : out STD_LOGIC	-- output valid
		);
	end component AES_CORE;
	constant NO_ROUNDS : NATURAL := lookupRounds(CV_SIZE);
	
	------------------------------------ States -----------------------------------------------

	type state_type is (idle,hash_sig,quote_p1,quote_p2,encr_p1,encr_p2,encr_write,store_encr,
	decr_p1,decr_p2,decr_write,store_decr,pause);
   signal state, next_state: state_type;
	
begin
	block_out <= Regblk(0) & Regblk(1) & Regblk(2) & Regblk(3);
	
	-- 3-bit Counter
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
	-- Regblk registers
	store_Regblk : process(clk)
	begin
		if rising_edge(clk) then
			if rst_blk = '1' or reset_n = '0' then
				Regblk(0) <= X"00000000";
				Regblk(1) <= X"00000000";
				Regblk(2) <= X"00000000";
				Regblk(3) <= X"00000000";
			elsif en_blk = '1' then
				if store_res = '1' then
					Regblk(0) <= result(0);
					Regblk(1) <= result(1);
					Regblk(2) <= result(2);
					Regblk(3) <= result(3);
				elsif quot_write = '1' then
					Regblk(0) <= quote_msg(127 downto 96);
					Regblk(1) <= quote_msg(95 downto 64);
					Regblk(2) <= quote_msg(63 downto 32);
					Regblk(3) <= quote_msg(31 downto 0);
				elsif hps_write = '1' then
					Regblk(to_integer(count)) <= hps_msg;
				end if;
			end if;
		end if;
	end process store_Regblk;
	
	AES_unit: component AES_CORE
	generic map(
		KEYLENGTH  =>  CV_SIZE, -- Size of keyblock (128, 192, 256 Bits)
		DECRYPTION =>  true			-- include decrypt datapath
		)
	port map(
		clk		=>   clk,
		data_in		  => Regblk,		-- payload to encrypt
		data_stable	  => data_stable,	-- flag valid payload
		keyword		  => secret_key(to_integer(count)),--secret_key(to_integer(count)),		-- word of original userkey
		keywordaddr	  => std_logic_vector(count),  -- keyword register address
		w_ena_keyword => w_ena_keyword,	-- write enable of keyword to wordaddr
		key_stable	  => key_stable,	-- key is complete and valid, start expansion
		decrypt_mode  => decrypt_mode,	-- decrypt='1',encrypt='0'
		keyexp_done	  => keyexp_done,	-- keyprocessing is done
		result		  => result,		-- output
		finished	  => finished	-- output valid
	);
	
	statemachine1 : process(clk,reset_n)
	begin  
		if reset_n = '0' then
			state <= idle;  
		elsif rising_edge(clk) then
			state <= next_state;     
		end if;  
	end process statemachine1;
	
	statemachine2 : process(state, encr_in, decr_in, quot_in, finished, quote_sha_done)
	begin  
		next_state <= state;
		-- Control Signals
		decr_out <= '0';
		encr_out <= '0';
		quot_out <= '0';
		-- Signals for SHA256
		quote_sha <= '0';
		-- Counter signals
		en_cnt <= '0';
		rst_cnt <= '0';
		-- Regblk Signals
		store_res <= '0';
		hps_write <= '0';
		quot_write <= '0';
		en_blk <= '0';
		rst_blk <= '0';
		-- AES Signals
		data_stable <= '0';
		w_ena_keyword <= '0';
		key_stable <= '0';
		decrypt_mode <= '0';
		
		case state is
			when idle =>
				if quot_in = '1' then
					quot_out <= '1';
					quote_sha <= '1';
					next_state <= hash_sig;
				elsif encr_in = '1' then
					next_state <= encr_p1;
				elsif decr_in = '1' then
					next_state <= decr_p1;
				end if;
			when hash_sig => -- HASH PCR || NONCE
				quot_out <= '1';
				quote_sha <= '1';
				if quote_sha_done = '1' then
					-- Write in quote msg into Regblk
					en_blk <= '1';
					quot_write <= '1';
					next_state <= quote_p1;
				else
					next_state <= hash_sig;
				end if;
			when quote_p1 => -- Writes in UDS to AES
				quote_sha <= '1';
				quot_out <= '1';
				w_ena_keyword <= '1';
				en_cnt <= '1';
				next_state <= quote_p1;
				-- Wait till secret key is fed
				if count = B"111" then
					next_state <= quote_p2;
				end if;
			when quote_p2 => -- Waits till encryption is done
				quote_sha <= '1';
				quot_out <= '1';
				key_stable <= '1';
				data_stable <= '1';
				if finished = '1' then
					store_res <= '1';
					en_blk <= '1';
					next_state <= pause;
				else
					next_state <= quote_p2;
				end if;
			when pause => -- Waits till user deasserts control signals
				rst_cnt <= '1';
				if quot_in = '0' and encr_in = '0' and decr_in = '0' then
					next_state <= idle;
				else
					next_state <= pause;
				end if;
			when encr_p1 => -- Writes in plaintext to be encrypted
				en_blk <= '1';
				hps_write <= '1';
				if encr_in = '1' then
					encr_out <= '1';
					en_cnt <= '1';
					next_state <= encr_p2;
				else
					next_state <= encr_p1;
				end if;
			when encr_p2 => -- Waits for user to load in next block
				if count = B"100" then
					rst_cnt <= '1';
					next_state <= encr_write;
				elsif encr_in = '0' then
					next_state <= encr_p1;
				else
					next_state <= encr_p2;
				end if;
			when encr_write => -- Writes in UDS
				encr_out <= '1';
				en_cnt <= '1';
				w_ena_keyword <= '1';
				if count = B"111" then
					next_state <= store_encr;
				else
					next_state <= encr_write;
				end if;
			when store_encr => -- Waits for ciphertext to be done and store it in Regblk
				encr_out <= '1';
				key_stable <= '1';
				data_stable <= '1';
				if finished = '1' then
					en_blk <= '1';
					store_res <= '1';
					rst_cnt <= '1';
					next_state <= pause;
				else
					next_state <= store_encr;
				end if;
			when decr_p1 => -- Writes in plaintext to be decrypted
				decrypt_mode <= '1';
				en_blk <= '1';
				hps_write <= '1';
				if decr_in = '1' then
					decr_out <= '1';
					en_cnt <= '1';
					next_state <= decr_p2;
				else
					next_state <= decr_p1;
				end if;
			when decr_p2 => -- Waits for user to load in next block
				decrypt_mode <= '1';
				if count = B"100" then
					rst_cnt <= '1';
					next_state <= decr_write;
				elsif decr_in = '0' then
					next_state <= decr_p1;
				else
					next_state <= decr_p2;
				end if;
			when decr_write => -- Writes in UDS
				decr_out <= '1';
				decrypt_mode <= '1';
				en_cnt <= '1';
				w_ena_keyword <= '1';
				if count = B"111" then
					next_state <= store_decr;
				else
					next_state <= decr_write;
				end if;
			when store_decr => -- Waits for output, then store it in Regblk
				decr_out <= '1';
				decrypt_mode <= '1';
				key_stable <= '1';
				data_stable <= '1';
				if finished = '1' then
					en_blk <= '1';
					store_res <= '1';
					rst_cnt <= '1';
					next_state <= pause;
				else
					next_state <= store_decr;
				end if;
		end case;
	end process statemachine2;

end behavior;
