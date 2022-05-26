unit uOpcodes;

{$mode ObjFPC}{$H+}

interface
uses
  SysUtils;

const
  OP_HALT  = 0;  // stops the program
  OP_CONST = 1;  // pushes a constant onto the stack
  OP_ADD   = 2;  // add 2 numbers and push result on the stack
  OP_SUB   = 3;  // subtract 2 numbers and push result on the stack
  OP_MUL   = 4;  // multiply 2 numbers and push result on the stack
  OP_DIV   = 5;  // divide 2 numbers and push result on the stack

  OP_COMPARE = 6;

  OP_JUMP_IF_FALSE = 7;
  OP_JUMP = 8;

  OP_GET_GLOBAL = 9;
  OP_SET_GLOBAL = 10;

  OP_POP = 11;

  OP_GET_LOCAL = 12;
  OP_SET_LOCAL = 13;
  OP_SCOPE_EXIT = 14;

function OpcodeToString(const Opcode: Byte): String;

implementation

function OpcodeToString(const Opcode: Byte): String;
begin
  case Opcode of
    OP_HALT          : Result := 'HALT';
    OP_CONST         : Result := 'CONST';
    OP_ADD           : Result := 'ADD';
    OP_SUB           : Result := 'SUB';
    OP_MUL           : Result := 'MUL';
    OP_DIV           : Result := 'DIV';
    OP_COMPARE       : Result := 'COMPARE';
    OP_JUMP_IF_FALSE : Result := 'JUMP_IF_FALSE';
    OP_JUMP          : Result := 'JUMP';
    OP_GET_GLOBAL    : Result := 'GET_GLOBAL';
    OP_SET_GLOBAL    : Result := 'SET_GLOBAL';
    OP_POP           : Result := 'POP';
    OP_GET_LOCAL     : Result := 'GET_LOCAL';
    OP_SET_LOCAL     : Result := 'SET_LOCAL';
    OP_SCOPE_EXIT    : Result := 'SCOPE_EXIT';
    otherwise          Result := 'OpcodeToString: Unknown opcode: ' + IntToStr(Opcode);
  end;
end;

end.

