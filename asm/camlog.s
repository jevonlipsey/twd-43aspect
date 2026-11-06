.macro HEX n
  mov ecx, \n
  mov r9, r8
  add r9, rcx
  mov r8, r9
1:
  mov edx, eax
  and edx, 15
  add dl, 48
  cmp dl, 57
  jbe 2f
  add dl, 7
2:
  dec r9
  mov byte ptr [r9], dl
  shr rax, 4
  dec ecx
  jnz 1b
.endm
  movaps xmm8, xmmword ptr [rsp+0x58]
  sub rsp, 0x78
  lea r8, [rsp+0x20]
  mov dword ptr [r8], 0x003d52
  add r8, 2
  mov rax, [rsp+0x78+0x90]
  HEX 16
  mov dword ptr [r8], 0x003d4120
  add r8, 3
  mov eax, [rbx+0x1c4]
  HEX 8
  mov dword ptr [r8], 0x003d5320
  add r8, 3
  mov eax, [rbx+0x1c8]
  HEX 8
  mov dword ptr [r8], 0x003d4620
  add r8, 3
  mov eax, [rbx+0x1cc]
  HEX 8
  mov dword ptr [r8], 0x003d4320
  add r8, 3
  mov rax, rbx
  HEX 16
  mov dword ptr [r8], 0x003d4720
  add r8, 3
  movzx eax, byte ptr [rbx+0x93]
  HEX 2
  mov dword ptr [r8], 0x0000000a
  lea rcx, [rsp+0x20]
  mov rax, 0x140bbf410
  call qword ptr [rax]
  add rsp, 0x78
  ret
