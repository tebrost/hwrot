Author: John Zhu
Copyright (c) 2018 University of Maryland Baltimore County

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


How to Use Optimized (Simon) Root of Trust

Control Signals
bits       3   |    2   |   1  |   0
signals  quote | extend | hash | reset

reset : Resets RegBlock only.
hash: Used to initiate a hash
extend : Used to initiate extend operation
quote : Initiate quote operation

Address Map:

Entity            |  Offset   | Width
------------------|-----------|----------
Control Signals   |  0x0      |  0x10
System ID         |  0x10     |  0x08
HPS Input         |  0x18     |  0x10
Regblock          |  0x28     |  0x10
PCR               |  0x38     |  0x10	

To execute hash, extend, and quote, just simply toggle bit and wait till control bit is 0 again.

For hash and quote, it is necessary to fill HPS Input buffer with 128 bit block before toggling control bits.

If want to start a new hash, or simply reset RegBlock after Quote operation, toggle reset bit. State machine prevents resetting during operations.

-- Test Vector
Perform Attestation on two message blocks M1 and M2. Then use Nonce to Quote measurement.
M1 = 101112131415161718191a1b1c1d1e1f
M2 = 202122232425262728292a2b2c2d2e2f
Nonce = 303132333435363738393a3b3c3d3e3f

Step 1: Hash the first 128-bit message block into HPS Input
mw ff200018 13121110
mw ff20001c 17161514
mw ff200020 1b1a1918
mw ff200024 1f1e1d1c

Step 2: Hash it.
mw ff200000 2

Step 3: Wait till hash is done by waiting for hash signal to go low.
md.b ff200000 10
Expected Result: 00000000 

Step 4: Read Regblock register
md.b ff200000 10
Expected Result: 745a72c241e5abf360f872557bc9b60d

Step 5: Using previous hash of 101112131415161718191a1b1c1d1e1f, Extend it by writing:
mw ff200000 4

Step 6: Wait till control signal goes back to 0. 
md.b ff200000 10
Expected Result: 00000000

Step 7: Write 0's into control register to exit Extend state.
mw ff200000 0

Step 8: Read new PCR value.
md.b ff200000 10
Expected Result: 84ab6a60a0832f966a78641669f19d88

Step 9: Reset the Regblk, then hash second message block
mw ff200000 1
mw ff200000 0
mw ff200018 23222120
mw ff20001c 27262524
mw ff200020 2b2a2928
mw ff200024 2f2e2d2c
mw ff200000 2

Step 10: Set hash control signal to 0. Read digest value of second block.
mw ff200000 0
md.b ff200028 10
Expected Result: 139d774563af403a01d6150dd1699ca4

Step 11: Extend new digest to get new PCR.
mw ff200000 4

Step 12: Wait till control signal goes back to 0. Then write set Extend control signal to 0.
md.b ff200000 10
mw ff200000 0

Step 13: Read new PCR value
md.b ff200038 10
Expected Value: 22495f214d9c329be340214a64ab8d26

Step 14: Quote using Nonce value 303132333435363738393a3b3c3d3e3f. First write in Nonce value into Msg Input
mw ff2000018 33323130
mw ff200001c 37363534
mw ff2000020 3b3a3938
mw ff2000024 3f3e3d3c

Step 15: Set Quote signal to 1
mw ff2000000 8

Step 16: Wait till Quote signal goes back to 0. Then set control signal to 0 to exit Quote state.
md.b ff200000 10
mw ff200000 0

Step 17: Read value in Regblock to view encrypted signature.
md.b ff200028 10
Expected Result: 67d14c03463a188a0d057fdd28733957


