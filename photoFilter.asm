.data
welcome:	.asciiz	"Welcome! Please enter the name of the file you would like to edit?  \n"
filterType:     .asciiz "Please enter the filter you would like to use.\nA list of filters are the following:\n0: Saturation, 1: Grayscale, 2: Edge-detection, 3: Brightness, 4: Hue, 5: Invert, 6: Shadow/Fill Light \n"
filterPercent:    .asciiz "Enter the percentage you want to wish to saturate (0 to 100)  \n"
brightnessPrompt:    .asciiz "Enter desired brightness percentage (0 to 200)\n"
shadowfillPrompt:    .asciiz "Enter desired shadow/fill light value (-255 to 255)\n"
redValue:    .asciiz "Enter hue modification value for red (0 to 255)\n"
blueValue:    .asciiz "Enter hue modification value for blue (0 to 255)\n"
greenValue:    .asciiz "Enter hue modification value for green (0 to 255)\n"
header: 	.space   54 	# bitmap header data stored here 
inputFileName:	.space	128 	# name of the input file, specified by user
outname: 	.asciiz  "OUTPUT_IMAGE.bmp"
buffer:		.space	1	# just here so that there are no compile time errors

######################################################################################################
# A program to process an image with multiple different filters. 
# The input image needs to be a .bmp image and the output will be the same type.
# The filters include saturation, grayscale, edge-detection, etc.
# Authors: Shaun Howard, Emilio Colindres, Bennet Sherman, Josh Tang, Kevin Perera
#
#	$s0 - the file descriptor
#	$s1 - the size of the data section of the image (after 54 byte offset)
#       $s2 - the pixel array of the bmp image
#######################################################################################################
.text
main:
	
	#print welcome string
	li		$v0, 4			# syscall 4, print string
	la		$a0, welcome		# load welcome string
	syscall
	
	#read filename
	li		$v0, 8			# syscall 8, read string
	la		$a0, inputFileName	# store string in inputFileName
	li		$a1, 128		# read at most 256 characters
	syscall
	
	# remove trailing newline
	li		$t0, '\n'		# we are looking for this character
	li		$t1, 128		# length of the inputFileName
	li		$t2, 0			# clear the current character
	
newLineLoop:
	beqz		$t1, newLineLoopEnd	# if end of string, jump to loop end
	subu		$t1, $t1, 1		# decrement the index
	lb		$t2, inputFileName($t1)	# load the character at current index position
	bne		$t2, $t0, newLineLoop	# if current character != '\n', jump to loop beginning
	li		$t0, 0			# else store null character
	sb		$t0, inputFileName($t1) # and overwrite newline character with null
	
newLineLoopEnd:
	
	#open input file
	li		$v0, 13			# syscall 13, open file
	la		$a0, inputFileName	# load filename address
	li 		$a1, 0			# read flag
	li		$a2, 0			# mode 0
	syscall
	move		$s0, $v0		# save file descriptor
	
	#read header data
	li		$v0, 14			# syscall 14, read from file
	move		$a0, $s0		# load file descriptor
	la		$a1, header		# load address to store data
	li		$a2, 54			# read 54 bytes
	syscall
	#move $s1, $v0
	lw		$s1, header+34		# store the size of the data section of the image
	
	
	
	#read image data into array
	li		$v0, 9		# syscall 9, allocate heap memory
	move 	        $a0, $s1	# load size of data section
	syscall
	move 	        $s2, $v0	# store the base address of the array in $s2
	
	li		$v0, 14		# syscall 14, read from file
	move 	        $a0, $s0	# load file descriptor
	move 	        $a1, $s2	# load base address of array
	move 	        $a2, $s1	# load size of data section
	syscall
	
	#close file
	move		$a0, $s0		# move the file descriptor into argument register
	li		$v0, 16			# syscall 16, close file
	syscall
	
#determine the filter the user wants to run by input
 read_filter_data:
 	
 	#add $s3,$s3,$t0
        #print filter type string
	li		$v0, 4			# syscall 4, print string
	la		$a0, filterType		# load filter selection string
	syscall
	
        #read filter type
	li		$v0, 5			# syscall 5, read integer (0 to 4)
	syscall
	
	#store filter type in $t4
	addi            $t4, $v0, 0      
	
	#************ NOW THE IMAGE IS IN AN ARRAY STARTING AT $S2 **********#
	
##########################################################################################
#IMPORTANT:
#pixel array starts at $s2. each pixel is stored as 3 hexadecimal values like 15 00 88
#the r g b values are stored backwards like b g r, i.e. b = 15, g = 00, r = 88 from above
#we must iterate through the array of pixels, each 24 bits or 3 bytes wide
#first byte = b, second byte = g, third byte = r
#hence, b would be 0($s2), g = 1($s2), and r = 2($s2), nextPixel = 3($s2)
##########################################################################################

#Perform filtering on pixel data
# $t4 = the type of filter to run (0 for saturation, 1 for grayscale, 2 for sobel edge detection, 
# 3 for brightness, 4 for hue, 5 for inversion, 6 for shadow fill)
filter_init:

	la $s3, buffer  #load the address of the buffer into $s3
	

	addi $t3, $zero, -1 #no filter, just exit
	beq $t3, $t4, nothing 
	
	addi $t3, $zero, 0
	beq $zero, $t4, saturation
	
	addi $t3, $zero, 1
	beq $t3, $t4, grayscale
	
	addi $t3, $zero, 2
	#beq $t3, $t4, edge_detect
	
	addi $t3, $zero, 3
	beq $t3, $t4, brightness
	
	addi $t3, $zero, 4
	beq $t3, $t4, hue
	
	addi $t3, $zero, 5
	beq $t3, $t4, invert
	
	addi $t3, $zero, 6
	beq $t3, $t4, shadowfill
	
saturation:
 
	#saturate each r g b value based on percentage given
	#min value is 0, max value is 255, use fraction of each value for new value
	#use base index for 3 values, have constants to determine bit offsets of R,G,B
        #counter starts at 0, equations like Bi = i + B, Gi = i + G, Ri = i + R
        #the idea here is to use srl and sll, dumping excess 1's from the MSB
	#load the current blue pixel value into $t6
	
	#print filter percentage string
	li $v0, 4			# syscall 4, print string
	la $a0, filterPercent	# load filter selection string
	syscall
	
        #read filter percentage
	li $v0, 5			# syscall 5, read integer (0 to 100)
	syscall
	mtc1 $v0, $f0
        cvt.s.w $f0, $f0
	
	addi $t5,$zero,100
	mtc1 $t5, $f3
        cvt.s.w $f3, $f3
        
        div.s $f0,$f0,$f3
        
        addi $t7,$zero,1
	mtc1 $t7, $f8
        cvt.s.w $f8, $f8
        
        mtc1 $zero, $f7
        cvt.s.w $f7, $f7
        move $t6, $s2	#load the image
	move $t4, $zero
	

sat_loop:  #Start the saturation loop
	
	lb $t0, 0($t6)
	lb $t1, 1($t6)
	lb $t2, 2($t6)
	
	sll $t0,$t0,24
	srl $t0,$t0,24
	sll $t1,$t1,24
	srl $t1,$t1,24
	sll $t2,$t2,24
	srl $t2,$t2,24
	
	#Start procedure to store max in s5 and min in s6
	blt $t0, $t1, t1t2max
     	blt $t0, $t2, t2maxt1min
     	move $s5, $t0
     	j t1t2min

t1t2min:

	blt $t1,$t2, mint1
	move $s6,$t2
	j endmaxmin
	
mint1:
	move $s6,$t1
	j endmaxmin
	
t2maxt1min:

	move $s5,$t2
	move $s6,$t1
	j endmaxmin
	
t1t2max:

	blt $t1,$t2, t2maxt0min
	move $s5,$t1
	j t0t2min
	
t2maxt0min:

	move $s5,$t2
	move $s6,$t0
	j endmaxmin
	
t0t2min:

	blt $t0,$t2, mint0
	move $s6,$t2
	j endmaxmin
	
mint0:
	move $s6,$t0

endmaxmin: # Max is in s5 and min is in s6
	
	# Converts max and min to floating point numbers
	mtc1 $s5, $f1
        cvt.s.w $f1, $f1
        mtc1 $s6, $f2
        cvt.s.w $f2, $f2
	
	# Stores RGB values to floating point
	mtc1 $t0, $f4
        cvt.s.w $f4, $f4
	mtc1 $t1, $f5
        cvt.s.w $f5, $f5
        mtc1 $t2, $f6
        cvt.s.w $f6, $f6
	
	# Multiply the min by the specified percentage
	mul.s $f2,$f2,$f0
	
	# Substract the product from the rgb values and the max value
	sub.s $f4,$f4,$f2
	sub.s $f5,$f5,$f2
	sub.s $f6,$f6,$f2
	sub.s $f9,$f1,$f2
	
	# If difference is greater than max skip and assign 1 to max, else max is assigned max divided by difference
	c.le.s $f2,$f7
	bc1t skipdiv
	div.s $f1,$f1,$f9
	j notzero
	
skipdiv:
	mov.s $f1,$f8
	
notzero:
	
	# Multiply RGB values by max	
	mul.s $f4,$f4,$f1
	mul.s $f5,$f5,$f1
	mul.s $f6,$f6,$f1
	
	# Convert to integers
	cvt.w.s $f4, $f4
	mfc1 $t0,$f4
	cvt.w.s $f5, $f5
	mfc1 $t1,$f5
	cvt.w.s $f6, $f6
	mfc1 $t2,$f6
	
	# Store RGB values in data buffer
	sb $t0, 0($s3)
	sb $t1, 1($s3)
	sb $t2, 2($s3)
	
	# Increse loop counters
	addi $t4, $t4, 3
	bge $t4, $s1, write_file # If end of file reached jump to write_file
	add $t6, $t6, 3
	add $s3, $s3, 3
	#else jump to start of the loop
	j sat_loop
	
# Initiate no filter mode
nothing:
	move $t0,$zero
	move $t1,$s2
	
# Loop to retrieve and store rgb values without any manipulation
nothing_loop:
	lb $t2,($t1)
	sb $t2,($s3)
	addi $s3,$s3,1
	addi $t1,$t1,1
	addi $t0,$t0,1
	
	blt $t0,$s1, nothing_loop
	
	li $v0, 1
	move $a0,$t2
	syscall
	
	j write_file

# Initiate grayscale filter
grayscale:
	#convert colors into grayscale
	move $t6, $s2	#load the image
	move $t4, $zero

# Grayscale filter loop
average_loop:	
	lb $t0, 0($t6)
	lb $t1, 1($t6)
	lb $t2, 2($t6)
	
	#Isolate RGB values
	sll $t0,$t0,24
	srl $t0,$t0,24
	sll $t1,$t1,24
	srl $t1,$t1,24
	sll $t2,$t2,24
	srl $t2,$t2,24
	
	add $t0, $t1, $t0	#add b and g
	add $t0, $t2, $t0	#add r
	div $t0, $t0, 3		#average the sum
	
	sb $t0, 0($s3)
	sb $t0, 1($s3)
	sb $t0, 2($s3)
	
	addi $t4, $t4, 3
	#increment counters to use next pixel
	#if we reach the end of the array, exit
	bge $t4, $s1, write_file
	add $t6, $t6, 3
	add $s3, $s3, 3
	#else jump to start of the loop
	j average_loop
	
edge_detect:
	#use sobel filter

# Initiate brightness filter	
brightness:
	move $t6, $s2	#load the image
	move $t4, $zero
	li $v0, 4			# syscall 4, print string
	la $a0, brightnessPrompt	# load filter selection string
	syscall
	li $v0, 5			# syscall 5, read integer (0 to 100)
	syscall
	move $t5, $v0
	addi $s5, $zero, 255
	mtc1 $s5, $f10
        cvt.s.w $f10, $f10
        addi $t7, $zero, 100
	bge $t5, $t7, brightness_loop_up
	j brightness_loop_down

# Brightness increase filter loop
brightness_loop_up:

	# Load RGB values
	lb $t0, 0($t6)
	lb $t1, 1($t6)
	lb $t2, 2($t6)
	
	# Convert parameters to floating point
	mtc1 $t5, $f1
        cvt.s.w $f1, $f1
	mtc1 $t7, $f2
        cvt.s.w $f2, $f2
        
	# Convert parameter to a percentage
	div.s $f1, $f1, $f2
	
	# Isolate RGB values then convert them to floating point
	sll $t0, $t0, 24
	srl $t0, $t0, 24
	sll $t1, $t1, 24
	srl $t1, $t1, 24
	sll $t2, $t2, 24
	srl $t2, $t2, 24
	
	mtc1 $t0, $f4
        cvt.s.w $f4, $f4
	mtc1 $t1, $f5
        cvt.s.w $f5, $f5
        mtc1 $t2, $f6
        cvt.s.w $f6, $f6
	
	# Multiply RGB values by the percentage calculated
	mul.s $f4, $f4, $f1
	mul.s $f5, $f5, $f1
	mul.s $f6, $f6, $f1
	
# Start procedure to cap RGB values at 255
	addi $t0, $zero, 0xFFFFFFFF
	addi $t1, $zero, 0xFFFFFFFF
	addi $t2, $zero, 0xFFFFFFFF
	
	c.lt.s $f10, $f4
	bc1t skipone_up
	
	cvt.w.s $f4, $f4
	mfc1 $t0, $f4
	
skipone_up:

	c.lt.s $f10, $f5
	bc1t skiptwo_up
	
	cvt.w.s $f5, $f5
	mfc1 $t1, $f5
	
skiptwo_up:

	c.lt.s $f10, $f6
	bc1t skipthree_up
	
	cvt.w.s $f6, $f6
	mfc1 $t2, $f6
	
skipthree_up:

#End capping procedure and store RGB values in data buffer
	sb $t0, 0($s3)
	sb $t1, 1($s3)
	sb $t2, 2($s3)
	
	addi $t4, $t4, 3
	#increment counters to use next pixel
	#if we reach the end of the array, exit
	bge $t4, $s1, write_file
	add $t6, $t6, 3
	add $s3, $s3, 3
	#else jump to start of the loop
	j brightness_loop_up

# Brightneess decrease filter	
brightness_loop_down:

	# Load RGB values
	lb $t0, 0($t6)
	lb $t1, 1($t6)
	lb $t2, 2($t6)
	
	# Convert parameters to floating point
	mtc1 $t5, $f1
        cvt.s.w $f1, $f1
	mtc1 $t7, $f2
        cvt.s.w $f2, $f2
        
        # Convert parameter to a percentage
	div.s $f1, $f1, $f2
	
	# Isolate and covert RGB values to floating point
	sll $t0, $t0, 24
	srl $t0, $t0, 24
	sll $t1, $t1, 24
	srl $t1, $t1, 24
	sll $t2, $t2, 24
	srl $t2, $t2, 24
	
	mtc1 $zero, $f0
        cvt.s.w $f0, $f0
	mtc1 $t0, $f4
        cvt.s.w $f4, $f4
	mtc1 $t1, $f5
        cvt.s.w $f5, $f5
        mtc1 $t2, $f6
        cvt.s.w $f6, $f6
	
	# Multiply RGB values by the percenage
	mul.s $f4, $f4, $f1
	mul.s $f5, $f5, $f1
	mul.s $f6, $f6, $f1
	
# Start procedure to cap RGB values at 255

	addi $t0, $zero, 0x00000000
	addi $t1, $zero, 0x00000000
	addi $t2, $zero, 0x00000000
	
	c.lt.s $f4, $f0
	bc1t skipone_down
	
	cvt.w.s $f4, $f4
	mfc1 $t0, $f4
	
skipone_down:

	c.lt.s $f5, $f0
	bc1t skiptwo_down
	
	cvt.w.s $f5, $f5
	mfc1 $t1, $f5
	
skiptwo_down:

	c.lt.s $f6, $f0
	bc1t skipthree_down
	
	cvt.w.s $f6, $f6
	mfc1 $t2, $f6

# End capping procedure and store RGB values in the data buffer	
skipthree_down:	
	sb $t0, 0($s3)
	sb $t1, 1($s3)
	sb $t2, 2($s3)
	
	addi $t4, $t4, 3
	#increment counters to use next pixel
	#if we reach the end of the array, exit
	bge $t4, $s1, write_file
	add $t6, $t6, 3
	add $s3, $s3, 3
	#else jump to start of the loop
	j brightness_loop_down

#Initiate hue filter		
hue:
	#convert colors into grayscale
	move $t6, $s2	#load the image
	move $t4, $zero
	li $v0, 4			# syscall 4, print string
	la $a0, redValue	# load filter selection string
	syscall
	li $v0, 5			# syscall 5, read integer (0 to 100)
	syscall
	move $t7,$v0
	
	li $v0, 4			# syscall 4, print string
	la $a0, greenValue	# load filter selection string
	syscall
	li $v0, 5			# syscall 5, read integer (0 to 100)
	syscall
	move $t8,$v0
	
	li $v0, 4			# syscall 4, print string
	la $a0, blueValue	# load filter selection string
	syscall
	li $v0, 5			# syscall 5, read integer (0 to 100)
	syscall
	move $t9,$v0
	
# Hue filter loop
hue_loop:
	# Load RGB values
	lb $t0, 0($t6)
	lb $t1, 1($t6)
	lb $t2, 2($t6)
	#Isolate them
	sll $t0, $t0, 24
	srl $t0, $t0, 24
	sll $t1, $t1, 24
	srl $t1, $t1, 24
	sll $t2, $t2, 24
	srl $t2, $t2, 24
	
	#Add the relavent hue information
	add $t0, $t0, $t9	
	add $t1, $t1, $t8
	add $t2, $t2, $t7
	
	#Store rgb values in the data buffer
	sb $t0, 0($s3)
	sb $t1, 1($s3)
	sb $t2, 2($s3)
	
	addi $t4, $t4, 3
	#increment counters to use next pixel
	#if we reach the end of the array, exit
	bge $t4, $s1, write_file
	add $t6, $t6, 3
	add $s3, $s3, 3
	#else jump to start of the loop
	j hue_loop

# Initiate invert filter
invert:
	move $t6, $s2	#load the image
	move $t0, $zero 	
	move $t4, $zero
	addi $t5, $zero, 0xFFFFFFFF

# Invert filter loop
invert_loop:
	# Load RGB values
	lb $t0, 0($t6)
	lb $t1, 1($t6)
	lb $t2, 2($t6)
	
	# Sustract RGB values from 255
	sub $t0, $t5, $t0 	
	sub $t1, $t5, $t1
	sub $t2, $t5, $t2
	
	# Store RGB values in data buffer
	sb $t0, 0($s3)
	sb $t1, 1($s3)
	sb $t2, 2($s3)
	
	# Increase loop conters
	addi $t4, $t4, 3
	bge $t4, $s1, write_file #If end of file reached exit to write file
	add $t6, $t6, 3
	add $s3, $s3, 3
	j invert_loop # If not jump to loop starting point

# Initiate shadow/lightfill filter
shadowfill:

	move $t6, $s2	#load the image
	move $t4, $zero
	li $v0, 4			# syscall 4, print string
	la $a0, shadowfillPrompt	# load filter selection string
	syscall
	li $v0, 5			# syscall 5, read integer (0 to 100)
	syscall
	move $t5, $v0
	addi $s5, $zero, 255
	#If parameter greater than zero branch to fill loop if not get it's absolute value and jump to shadow loop
	bgez $t5, fill_loop	
	sra $t1, $t5, 31   
	xor $t5, $t5, $t1   
	sub $t5, $t5, $t1
	j shadow_loop

#Light fill filter loop
fill_loop:

	# Load and isolate RGB values
	lb $t0, 0($t6)
	lb $t1, 1($t6)
	lb $t2, 2($t6)
	
	sll $t7, $t0, 24
	srl $t7, $t7, 24
	sll $t8, $t1, 24
	srl $t8, $t8, 24
	sll $t9, $t2, 24
	srl $t9, $t9, 24

# Adds specifed value to RGB values and start capping procedure to cap at 255. Then store the values in the data buffer
	sub $t7, $s5, $t7
	sub $t8, $s5, $t8
	sub $t9, $s5, $t9
	
	blt $t7, $t5, fillskiponeup
	add $t0, $t5, $t0
	sb $t0, 0($s3)
	j filloneup
	
fillskiponeup:

	addi $t0, $zero, 0xFFFFFFFF
	sb $t0, 0($s3)
	
filloneup:

	blt $t8, $t5, fillskiptwoup
	add $t1, $t5, $t1
	sb $t1, 1($s3)
	j filltwoup
	
fillskiptwoup:

	addi $t1, $zero, 0xFFFFFFFF
	sb $t1, 1($s3)
	
filltwoup:

	blt $t9, $t5, fillskipthreeup
	add $t2, $t5, $t2
	sb $t2, 2($s3)
	j fillthreeup
	
fillskipthreeup:

	addi $t2, $zero, 0xFFFFFFFF
	sb $t2, 2($s3)
	
fillthreeup:
# End of capping and store procedure	
	addi $t4, $t4, 3
	#increment counters to use next pixel
	#if we reach the end of the array, exit
	bge $t4, $s1, write_file
	add $t6, $t6, 3
	add $s3, $s3, 3
	#else jump to start of the loop
	j fill_loop
	
# Shadow filter loop
shadow_loop:

	# Load and isolate RGB values
	lb $t0, 0($t6)
	lb $t1, 1($t6)
	lb $t2, 2($t6)
	
	sll $t7, $t0, 24
	srl $t7, $t7, 24
	sll $t8, $t1, 24
	srl $t8, $t8, 24
	sll $t9, $t2, 24
	srl $t9, $t9, 24
	
# Substracts specifed value from RGB values and start capping procedure to cap at 0. Then store the values in the data buffer
	blt $t7, $t5, shadowskiponedown
	sub $t0, $t0, $t5
	sb $t0, 0($s3)
	j shadowonedown
	
shadowskiponedown:

	addi $t0, $zero, 0x00000000
	sb $t0, 0($s3)
	
shadowonedown:

	blt $t8, $t5, shadowskiptwodown
	sub $t1, $t1, $t5
	sb $t1, 1($s3)
	j shadowtwodown
	
shadowskiptwodown:

	addi $t1, $zero, 0x00000000
	sb $t1, 1($s3)
	
shadowtwodown:
	
	blt $t9, $t5, shadowskipthreedown
	sub $t2, $t2, $t5
	sb $t2, 2($s3)
	j shadowthreedown
	
shadowskipthreedown:

	addi $t2, $zero, 0x00000000
	sb $t2, 2($s3)
	
shadowthreedown:
# End of capping and store procedure		
	addi $t4, $t4, 3
	#increment counters to use next pixel
	#if we reach the end of the array, exit
	bge $t4, $s1, write_file
	add $t6, $t6, 3
	add $s3, $s3, 3
	#else jump to start of the loop
	j shadow_loop

exit:
		
write_file:
	
	#open output file
	li	$v0, 13
	la	$a0, outname
	li	$a1, 1		#1 to write, 0 to read
	li	$a2, 0
	syscall
	move	$t1, $v0	#output file descriptor in $s2
	
	li	$v0, 15		#prep $v0 for write syscall
	move 	$a0, $t1
	la	$a1, header
	addi    $a2,$zero,54
	syscall
	#write to output file
	li	$v0, 15		#prep $v0 for write syscall
	move 	$a0, $t1
	la	$a1, buffer
	move   $a2,$s1
	syscall
	
	#close file
	move	$a0, $s2
	li	$v0, 16
	syscall

leave:
	#nicely terminate program
	li 	$v0, 10
	syscall
