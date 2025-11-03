
These are the reference PPA values for the design synthesised at slow corner:



Target clock period: 6 ns

Target Area: 22000 μm²

Target Power: 800 μW




Q. The project mentions that there must be "a maximum of two ports can be used to read data. In other words, in a single clock cycle, you can read a maximum of two addresses".
Are these 2 read ports for reading from all four files together {A.dat, B.dat, N.dat, Input.dat}?
Or are these 2 read ports only for Input.dat? 
Are expected to read in entire data from {A.dat, B.dat, N.dat} initially and store them in viterbi decoder, and then onwards read 2 addresses from Input.dat each clock cycle?

Also, what is the maximum length of each sequence of input observations (number of time steps T) ?
Picture of sgopal GOPALAKRISHNAN SRINIVASAN
In reply to Balaseshan Nemana
Re: Doubts regarding project
by sgopal GOPALAKRISHNAN SRINIVASAN - Tuesday, 21 October 2025, 5:29 AM
You can have at most 2 read ports for each memory. Create A_mem, B_mem, N_mem, and Input_mem using RegisterFile or Vector in Bluespec. You are expected to load the contents of the DAT file into the respective memories in the beginning of the simulation. Create interface methods for each kind of memory so that you can read from two addresses every cycle during the course of the simulation.

The Viterbi decoder module (your design) should output the read/write addresses every cycle and process the received data.


Q.Regarding the values in the prob. transition matrix are all test cases such that there are no zeroes in the P matrix or do we have edge cases where that happens as well. Asking this because ln(0) is undefined ad values close to it tend near infinity. I am assuming that since all probabilities are given in the natural log format they will all be well defined values, is this assumption valid??



Picture of Nikhitha Atyam
In reply to ee22b154 VISVESHWAR JAY SHANKAR
Re: Doubt about the prob. matrix structure
by Nikhitha Atyam - Wednesday, 22 October 2025, 2:05 AM
Yes, you can safely assume no zeroes in the probability matrix and also in its logarithmic format.


Q.
What rounding mode convention should be implemented in the floating-point adder to ensure accurate precision?

Picture of Nikhitha Atyam
In reply to Shridula A
Rounding Conventions in Floating-Point adder
by Nikhitha Atyam - Monday, 27 October 2025, 10:32 AM
Use the default IEEE 754 single precision floating point arithmetic rounding mode - "Round to nearest, ties to even"


Q. Is this restriction only for the math related to implementing floating point addition, or do we need to follow this in other cases like when we want to increment or decrement an index register, or while addressing the memory?

Picture of cs24s025 S K HARI KHESHAV
In reply to ee22b010 NAVAJYOTH B KRISHNAN
Regarding the restriction on the usage of + and *
by cs24s025 S K HARI KHESHAV - Monday, 27 October 2025, 10:12 PM
Hi, 

Sorry for the late reply.

For any kind of for loop directly using + is fine. 

Anything else please try to use implemented add methods/functions.



Regards,


Does this(the constraint on * and +) also involve things like index translation and subtraction or addition logic inside the floating point module??
Picture of cs24s025 S K HARI KHESHAV
In reply to ee22b154 VISVESHWAR JAY SHANKAR
Re: Regarding the restriction on the usage of + and *
by cs24s025 S K HARI KHESHAV - Tuesday, 28 October 2025, 7:59 PM
Index translation can be done using * and +.

But subtraction and addition logic inside floating point should have the constraints applied.

