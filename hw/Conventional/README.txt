Author: John Zhu
Copyright (c) 2018 University of Maryland Baltimore County

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.



How to Use Conventional (SHA + AES) Root of Trust

-- Control Signals ---------------------------------------------------------------------------------------------------------------------

bits        9        8         7         6       5        4        3-2       1       0
signals   quote | decrypt | encrypt | extend | hash | overwrite | bytes | msgend | msgfeed
	
msgfeed: Used to feed in 32 bit blocks (Only for HASH and Quote. The reason for this is because there is currently two wrappers)
msgend: Used to indicate that last 32-bit input block was the last part.
bytes: Indicates which bytes of 32-bit input block are valid. 00 - All. 01- First block. 02 - First two blocks. 03 - First three blocks.
overwrite : Overwrites FIPS-default for one hash operation. After one hash operation, FIPS defaults are reset to default values.
hash: Initiates hash. Requires software interrupts to feed in message
extend : Initiates extend operation.
encrypt, decrypt, and quote: Initiates encrypt, decrypt, and quote operations. Requires software interrupts to feed in nonce or messages

Address Map:
Entity            |  Offset   | Width
------------------|-----------|----------
Control Signals   |  0x0      |  0x10
Msg Input         |  0x10     |  0x04
Digest Register   |  0x14     |  0x20
PCR Register      |  0x34     |  0x20
Cipher Output     |  0x54     |  0x10

-- Procedure ---------------------------------------------------------------------------------------------------------------------------
---- Read Registers
To read the registers, such as Digest or PCR registers, use the md command.
Example: Read PCR register: md.b ff200034 20. Reads entire 16 bytes, or 32 nibbles.
---- Execute Commands
To execute commands, control control register at memory address 0xff20 0000 using the mw commands. The following section gives examples of how to execute.

---- Example: How to HASH "hi"
Step 1 : Write "hi"
mw ff200010 00006968

Step 2 : Tell SHA256 Engine to hash only the first two bytes of Msg Input.
mw ff200000 2b. --> 2b --> 0010 1011 -> hash = 1, bytes = 2, msgend = 1, msgfeed = 1

Step 3: Wait till hash is 0. Once you see a zero and signal end, zero out signal.
mw ff200000 0

Step 4: Read the resulting hash from digest register.
md.b ff200010 10  
Result: 8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4
-- Note: It is impossible to hash a null message with current SHA256 engine.

---- Example: HASH Multiple 32 bit blocks
In this example, we will hash abcdefghijkl
Step 1: Write in the message fragment abcd, which is dcba in little endian.
mw ff200010 64636261

Step 2: Initate a hash by setting hash control signal to 1.
mw ff200000 20

Step 3: Hash message with corresponding bytes. In the example below, the number of bytes hashed is 4, so bytes = 00. Since hash is already initiated, the hash control signal no longer matters.
mw ff200000 X1

Step 3 : Wait till msgfeed signal is zero. At that point, set msgfeed signal to 0.
mw ff200000 X0

Step 4: Repeat step 1 - 3 if you want to continue writing in 32 bit blocks. In the example, you would write:
mw ff200010 68676665
mw ff200000 X1
Wait till msgfeed signal is zero.
mw ff200000 X0

Step 5: Write in last message fragment by feeding the last block and setting end bit to 1 at the same time.
mw ff200010 6c6b6a69
mw ff200000 23

Step 6: Wait till end signal is zero. If zero, then write in zero.
mw ff200000 0.

Step 7: Read digest result
md.b ff200014 20
Result: d682ed4ca4d989c134ec94f1551e1ec580dd6d5a6ecde9f3d35e6e4a717fbde4

---- Example: EXTEND Digest
Step 1: Set extend signal to high. end, hash, and bytes signals are ignored.
mw ff200000 40

Step 2: Wait till extend returns a zero. Once you see a zero, write in zero.
mw ff200000 0

---- Example: Overwrite FIPS Default
Write in 000102030405060708090a0b0c0d0e0f
Step 1: Write in Left most word. 
mw ff200010 030201000

Step 2: Overwrite by setting overwrite bit to high
mw ff200000 10

Step 3: Once overwrite signal is zero, write zero.
mw ff200000 0

Step 4: Repeat steps 1-3 8 times.

Step 5: Now you hash. 
After one message (2^16 bit message), FIPS defaults are reset back to default values.

-- Encrypt and Decrypt
These operations require using software interrupts to find write in messages. However, instead of using msgfeed to do so, it uses the encrypt and decrypt signals respectively. This is not meant to be an optimization, it was because there are two state machines. Thus, there would be two state machines that would drive the same msgfeed_out signal. I didn't want to complicate how msgfeed_out would be driven, so I didn't use it for the RTR wrapper.

---- Example: Encrypt or Decrypt 000102030405060708090a0b0c0d0e0f
Step 1: Write in 32-bit block. Start with leftmost word. 
mw ff200010 030201000. DO NOT FEED 0f0e0d0c until the end.

Step 2: Initiate operation
mw ff200000 80 or 100 for encrypt or decrypt respectively

Step 3: Wait till encrypt/decrypt signal is low. Then write in zero.
mw ff200000 0

Step 4: Repeat step 1-3 four times.

Step 5: After writing in message, wait till control signal bit is low. Cipher Output will contain valid output.

---- Example: Quote. Operation is similar to hash

Step 1: Write in nonce block part
mw ff200010 XXXXXXXX

Step 2: Initiate Quote and write in message
mw ff200000 201

Step 3: Once msgfeed signal is low, write in zero for msgfeed
mw ff200000 200

Step 4: Repeat steps 1-3 four times.

Step 5: After repeating steps 1-3 four times, wait till quote signal is low. Signature will be in Cipher Output.

-- Test Vector
---- Initial Values
UDS= 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
NONCE = 303132333435363738393a3b3c3d3e3f
PCR= 0000000000000000000000000000000000000000000000000000000000000000
M1 = 101112131415161718191a1b1c1d1e1f

Step 1: Hash M1.
mw ff200010 13121110
mw ff200000 21
mw ff200000 20
mw ff200010 17161514
mw ff200000 21
mw ff200000 20
mw ff200010 1b1a1918
mw ff200000 21
mw ff200000 20
mw ff200010 1f1e1d1c
mw ff200000 23

Step 2: Wait till control signals go to 0s. Then reset control registers to 0s and read digest register.
md.b ff200000 10. Expected result: 00000000
mw ff200000 0
md.b ff200014 20. Expected result: fc2e2c73072bfa2bda03ff9307472debd3cc8105028a8a9e235e35ba8d2e37f4 = H(M1)

Step 3: Extend current digest to update PCR. Wait till control signal goes back to 0, then read new PCR value.
mw ff200000 40
md.b ff200000 10. Expected result: 00000000
mw ff200000 0
md.b ff200034 10. Expected result: 6d87a9d906cc6aeee489b5b0d8c07540e08f12028f53426127a5625e9d99170a = PCR.

Step 4: Quote it using NONCE = 303132333435363738393a3b3c3d3e3f
mw ff200010 33323130
mw ff200000 201
mw ff200000 200
mw ff200010 37363534
mw ff200000 201
mw ff200000 200
mw ff200010 3b3a3938
mw ff200000 201
mw ff200000 200
mw ff200010 3f3e3d3c
mw ff200000 201

Step 5: Wait till control signals go to 0.
md.b ff200000 10. Expected result: 00000000

Step 6: Read encrypted signature
md.b ff200054 10. Expected result: 0ed38d804bb75d237ce5d409bf041a4a
