# how to

Connect a programmer to Peppy's firmware SPI flash (see
https://www.chromium.org/chromium-os/developer-information-for-chrome-os-devices/acer-c720-chromebook
for the position of the chip) and create a copy of the contents:

    make flash_read
    # or if your programmer is not the ch341a_spi:
    # make FLASHROM_PROGRAMMER=name_of_the_programmer flash_read

Now the build script can extract the necessary blobs from the firmware and build everything:

    make

Write the resulting `peppy-linuxboot.rom` image to the flash:

    make flash_write
    # again, you can use FLASHROM_PROGRAMMER for other programmers

