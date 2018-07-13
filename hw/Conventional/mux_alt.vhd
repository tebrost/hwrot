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

entity mux_alt is 

	port(
		data0x	: in	std_logic_vector(31 downto 0);
		data1x	: in	std_logic_vector(511 downto 0);
		sel	   : in	std_logic;
		step : in unsigned(3 downto 0);
		result	: out	std_logic_vector(31 downto 0)
	);

end mux_alt;


architecture arch1 of mux_alt is

	signal tmp1 : std_logic_vector(31 downto 0);

begin
	-- Splits PCR and Digest into 16 32-bit blocks
	mux1: process(step)	
	begin
		case step is
			when X"0" => tmp1 <=  data1x(511 downto 480);
			when X"1" => tmp1 <=  data1x(479 downto 448);
			when X"2" => tmp1 <=  data1x(447 downto 416);
			when X"3" => tmp1 <=  data1x(415 downto 384);
			when X"4" => tmp1 <=  data1x(383 downto 352);
			when X"5" => tmp1 <=  data1x(351 downto 320);
			when X"6" => tmp1 <=  data1x(319 downto 288);
			when X"7" => tmp1 <=  data1x(287 downto 256);
			when X"8" => tmp1 <=  data1x(255 downto 224);
			when X"9" => tmp1 <=  data1x(223 downto 192);
			when X"a" => tmp1 <=  data1x(191 downto 160);
			when X"b" => tmp1 <=  data1x(159 downto 128);
			when X"c" => tmp1 <=  data1x(127 downto 96);
			when X"d" => tmp1 <=  data1x(95 downto 64);
			when X"e" => tmp1 <=  data1x(63 downto 32);
			when X"f" => tmp1 <=  data1x(31 downto 0);
		end case;
	end process mux1;
	
	-- Selects either hps message or a block from mux1 to be the output
	mux2 : process(sel,step) 
	begin
		case sel is
			when '0' => result <= data0x;
			when '1' => result <= tmp1;
			when others => result <= (others => '1');
		end case;
		
	end process mux2;

end arch1;
