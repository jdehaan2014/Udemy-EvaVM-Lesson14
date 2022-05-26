unit uDisassembler;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}
{$ModeSwitch implicitfunctionspecialization}

interface

uses
  SysUtils, uValue, uArray, uGlobals;

type
  TDisassembler = record
    public
      procedure Init(AGlobal: PGlobal);
      procedure Disassemble(CO: TCodeObj);
    private
      Global: PGlobal;
      function DisassembleInstruction(CO: TCodeObj; OffSet: Integer): Integer;
      function DisassembleSimple(CO: TCodeObj;  Opcode: Byte; OffSet: Integer): Integer;
      function DisassembleWord(CO: TCodeObj;  Opcode: Byte; OffSet: Integer): Integer;
      function DisassembleConst(CO: TCodeObj; Opcode: Byte; OffSet: Integer): Integer;
      function DisassembleCompare(CO: TCodeObj; Opcode: Byte; OffSet: Integer): Integer;
      function DisassembleJump(CO: TCodeObj; Opcode: Byte; OffSet: Integer): Integer;
      function DisassembleGlobal(CO: TCodeObj; Opcode: Byte; OffSet: Integer): Integer;
      function DisassembleLocal(CO: TCodeObj; Opcode: Byte; OffSet: Integer): Integer;

      procedure DumpBytes(CO: TCodeObj; OffSet, Count: Integer);
      procedure PrintOpcode(const Opcode: Byte);
      function ReadWordAt(CO: TCodeObj; OffSet: Integer): UInt16;
  end;

implementation
uses uCommon, uOpcodes;

const
  InverseCompareOps: array of string = ('<', '>', '=', '>=', '<=', '<>');

{ TDisassembler }

procedure TDisassembler.Init(AGlobal: PGlobal);
begin
  Global := AGlobal;
end;

// Disassembles a code unit.
procedure TDisassembler.Disassemble(CO: TCodeObj);
var
  OffSet: Integer = 0;
begin
  WriteLn(LineEnding, '-------------- Disassembly: ', CO.Name, ' -------------', LineEnding);

  while OffSet < CO.Code.Count do
    begin
      OffSet := DisassembleInstruction(CO, OffSet);
      Writeln;
    end;
  Writeln;
end;

// Disassembles an individual instruction.
function TDisassembler.DisassembleInstruction(CO: TCodeObj; OffSet: Integer): Integer;
var
  OpCode: Byte;
begin
  WriteFmt('%.4x    ', [Offset]);
  OpCode := CO.Code[OffSet];
  case Opcode of
    OP_HALT:
      Result := DisassembleSimple(CO, Opcode, OffSet);
    OP_ADD..OP_DIV:
      Result := DisassembleSimple(CO, Opcode, OffSet);
    OP_CONST:
      Result := DisassembleConst(CO, Opcode, OffSet);
    OP_COMPARE:
      Result := DisassembleCompare(CO, Opcode, OffSet);
    OP_JUMP_IF_FALSE, OP_JUMP:
      Result := DisassembleJump(CO, Opcode, OffSet);
    OP_GET_GLOBAL, OP_SET_GLOBAL:
      Result := DisassembleGlobal(CO, Opcode, OffSet);
    OP_POP:
      Result := DisassembleSimple(CO, Opcode, OffSet);
    OP_GET_LOCAL, OP_SET_LOCAL:
      Result := DisassembleLocal(CO, Opcode, OffSet);
    OP_SCOPE_EXIT:
      Result := DisassembleWord(CO, Opcode, OffSet);
    otherwise
      WriteLnFmt('Disassemble instruction: no disassembly for %s', [OpcodeToString(Opcode)]);
      Result := OffSet+1;
  end;
end;

function TDisassembler.DisassembleSimple(CO: TCodeObj; Opcode: Byte;
  OffSet: Integer): Integer;
begin
  DumpBytes(CO, OffSet, 1);
  PrintOpcode(Opcode);
  Result := OffSet + 1;
end;

function TDisassembler.DisassembleWord(CO: TCodeObj; Opcode: Byte;
  OffSet: Integer): Integer;
begin
  DumpBytes(CO, OffSet, 2);
  PrintOpcode(Opcode);
  Write(CO.Code[OffSet+1]);
  Result := OffSet + 2;
end;

function TDisassembler.DisassembleConst(CO: TCodeObj; Opcode: Byte; OffSet: Integer): Integer;
var
  ConstIndex: Byte;
begin
  DumpBytes(CO, OffSet, 2);
  PrintOpcode(Opcode);
  ConstIndex := CO.Code[OffSet+1];
  Write(ConstIndex, ' (', ValueToString(CO.Constants[ConstIndex]), ')');
  Result := OffSet + 2;
end;

function TDisassembler.DisassembleCompare(CO: TCodeObj; Opcode: Byte;
  OffSet: Integer): Integer;
var
  CompareOP: Byte;
begin
  DumpBytes(CO, OffSet, 2);
  PrintOpcode(Opcode);
  CompareOP := CO.Code[OffSet+1];
  Write(CompareOP, ' (', InverseCompareOps[CompareOP], ')');
  Result := OffSet + 2;
end;

function TDisassembler.DisassembleJump(CO: TCodeObj; Opcode: Byte;
  OffSet: Integer): Integer;
var
  Address: UInt16;
begin
  DumpBytes(CO, OffSet, 3);
  PrintOpcode(Opcode);
  Address := ReadWordAt(CO, OffSet+1);
  WriteFmt('%.4x    ', [Address]);
  Result := OffSet + 3;
end;

// Disassembles global variable instruction
function TDisassembler.DisassembleGlobal(CO: TCodeObj; Opcode: Byte;
  OffSet: Integer): Integer;
var
  GlobalIndex: Byte;
begin
  DumpBytes(CO, OffSet, 2);
  PrintOpcode(Opcode);
  GlobalIndex := CO.Code[OffSet+1];
  Write(GlobalIndex, ' (', Global^.get(GlobalIndex).Name, ')');
  Result := OffSet + 2;
end;

function TDisassembler.DisassembleLocal(CO: TCodeObj; Opcode: Byte;
  OffSet: Integer): Integer;
var
  LocalIndex: Byte;
begin
  DumpBytes(CO, OffSet, 2);
  PrintOpcode(Opcode);
  LocalIndex := CO.Code[OffSet+1];
  //Write(LocalIndex, ' (', CO.Locals[LocalIndex].Name, ')');
  Write(LocalIndex);
  // std::cout << (int)localIndex << " (" << co->locals[localIndex].name << ")";
  Result := OffSet + 2;
end;

// Dumps raw memory from the bytecodes
procedure TDisassembler.DumpBytes(CO: TCodeObj; OffSet, Count: Integer);
var
  i: Integer;
  s: String = '';
begin
  for i:=0 to Count - 1 do
    s += HexStr(CO.Code[OffSet+i] and $FF, 2) + ' ';
  WriteFmt('%0:-12s', [s]);
end;

procedure TDisassembler.PrintOpcode(const Opcode: Byte);
begin
  WriteFmt('%0:-20s', [OpcodeToString(Opcode)]);
end;

function TDisassembler.ReadWordAt(CO: TCodeObj; OffSet: Integer): UInt16;
begin
  Result := (CO.Code[OffSet] shl 8) or (CO.Code[OffSet+1]);
end;

end.

