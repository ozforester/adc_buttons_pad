
# Copyright (c) 2021 ozforester. All rights reserved.
# Use of this source code is goverened by a MIT license
# that can be found in the LICENSE file.

TARGET	 = adc_buttons_pad
SOURCES := $(wildcard *.c)
OBJECTS  = $(SOURCES:.S=.o)
OPT = -Os

all:
	avr-gcc -DF_CPU=4000000LL -c -Wall ${OPT} -mmcu=atmega8 -o ${TARGET}.o ${TARGET}.S
	avr-gcc -Wall -Os -mmcu=atmega8 -o ${TARGET} ${TARGET}.o
	avr-objcopy -O ihex ${TARGET} ${TARGET}.hex
	avr-size ${TARGET}
	avr-size ${TARGET}.hex

flash:
	avrdude -c usbasp -p m8 -B 3 -U flash:w:${TARGET}.hex

clean:
	rm -f $(OBJECTS) $(TARGET) $(TARGET).hex $(TARGET).o
