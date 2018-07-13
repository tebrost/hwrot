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

entity hex_display is
	port(
		hex_input : in std_logic_vector(3 downto 0);
		hex_output : out std_logic_vector(6 downto 0)
	);
end hex_display;

architecture behavior of hex_display is
begin
	process(hex_input) 
	begin
		case hex_input is
			when x"0" => hex_output <= B"1000000";
			when x"1" => hex_output <= B"1111001";
			when x"2" => hex_output <= B"0100100";
			when x"3" => hex_output <= B"0110000";
			when x"4" => hex_output <= B"0011001";
			when x"5" => hex_output <= B"0010010";
			when x"6" => hex_output <= B"0000010";
			when x"7" => hex_output <= B"1111000";
			when x"8" => hex_output <= B"0000000";
			when x"9" => hex_output <= B"0010000";
			when x"a" => hex_output <= B"0001000";
			when x"b" => hex_output <= B"0000011";
			when x"c" => hex_output <= B"1000110";
			when x"d" => hex_output <= B"0100001";
			when x"e" => hex_output <= B"0000110";
			when x"f" => hex_output <= B"0001110";
		end case;
	end process;
end behavior;

