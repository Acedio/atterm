#ifndef KEYBOARD_H
#define KEYBOARD_H

void kb_init();

void kb_enable();
void kb_disable();

unsigned char kb_bytes_ready();
unsigned char kb_read(unsigned char* out);

#endif  // KEYBOARD_H
