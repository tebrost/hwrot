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

entity dflipflop_alt is 
	generic (
		IN_SIZE : positive := 32;
		OUT_SIZE : positive := 128;
		STEP_SIZE : positive := 2
	);
	port(
		clk : in std_logic;
		reset : in std_logic;
		en : in std_logic;
		step	: in	unsigned(1 downto 0);--std_logic_vector(OUT_SIZE/IN_SIZE-1 downto 0);
		d_in	: in	unsigned(IN_SIZE-1 downto 0);
		xor_in : in unsigned(IN_SIZE-1 downto 0);
		d_out	: out	unsigned(OUT_SIZE-1 downto 0)
	);

end dflipflop_alt;

architecture behavior of dflipflop_alt is

	signal reg0 : unsigned(31 downto 0);
	signal reg1 : unsigned(31 downto 0);
	signal reg2 : unsigned(31 downto 0);
	signal reg3 : unsigned(31 downto 0);
	
begin
	
	reg0_unit : process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				reg0 <= (others=>'0');
			elsif en = '1' and step = 0 then
				reg0 <= d_in xor xor_in;
			end if;
		end if;
	end process reg0_unit;
	
	reg1_unit : process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				reg1 <= (others=>'0');
			elsif en = '1' and step = 1 then
				reg1 <= d_in xor xor_in;
			end if;
		end if;
	end process reg1_unit;
	
	reg2_unit : process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				reg2 <= (others=>'0');
			elsif en = '1' and step = 2 then
				reg2 <= d_in xor xor_in;
			end if;
		end if;
	end process reg2_unit;
	
	reg3_unit : process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				reg3 <= (others=>'0');
			elsif en = '1' and step = 3 then
				reg3 <= d_in xor xor_in;
			end if;
		end if;
	end process reg3_unit;
	
	d_out <= reg3 & reg2 & reg1 & reg0;
	
	
end behavior;
