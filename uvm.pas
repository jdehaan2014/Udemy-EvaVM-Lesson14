unit uVM;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}
{$ModeSwitch implicitfunctionspecialization}

interface

uses
  SysUtils, uOpcodes, uValue, uArray, uParser, uCompiler, uGlobals;

const
  //cMaxFrames = 256;
  cMaxStack = 65536; // 64K stack


type

  TEvaVM = record
    //Code: TCode;
    ip: PByte;       // instruction pointer
    sp: PValue;      // stack pointer
    bp: PValue;      // base (frame) pointer
    Stack: array[0..cMaxStack-1] of TValue;
    Global: PGlobal;
    Parser: TParser;
    Compiler: TCompiler;
    CO: TCodeObj;
    constructor Create(AGlobal: PGlobal);
    procedure setGlobalVariables;
    function Exec(const AProgram: String): TValue;
    function Eval: TValue;
    function ReadByte: Byte;
    function ReadShort: UInt16;
    function ReadConst: TValue;
    procedure Push(Value: TValue);
    function Pop: TValue;
    procedure BinaryOp(const Op: Byte);
    function toAddress(const Index: UInt16): PByte;
    function Peek(const OffSet: Integer = 0): TValue;
    procedure PopN(const Count: Integer);
  end;

  generic function CompareValues<T>(const Op: Byte; V1, V2: T): Boolean;

implementation
uses uLogger, uAST;

generic function CompareValues<T>(const Op: Byte; V1, V2: T): Boolean;
begin
  case Op of
    0: Result := V1 < V2;
    1: Result := V1 > V2;
    2: Result := V1 = V2;
    3: Result := V1 >= V2;
    4: Result := V1 <= V2;
    5: Result := V1 <> V2;
  end;
end;


{ EvaVM }

constructor TEvaVM.Create(AGlobal: PGlobal);
begin
  Global := AGlobal;
  setGlobalVariables;
end;

// initialize global variables and function
procedure TEvaVM.setGlobalVariables;
begin
  Global^.addConstant('version', 1);
  Global^.addConstant('y', 20);
end;

function TEvaVM.Exec(const AProgram: String): TValue;
var
  AST: TExpr;
begin
  // 1. Parse the program
  Parser := TParser.Create('(begin ' + AProgram + ')');
  AST := Parser.Parse;
  //AST.Print;

  // 2. Compile the program to byte code
  Compiler.Init(Global);
  CO := Compiler.Compile(AST);

  // Set instruction pointer
  ip := @CO.Code.Data[0]; // set instruction pointer to the start of the code
  sp := @Stack[0];        // set stack pointer to start of the stack
  bp := @Stack[0];        // init the base pointer to beginning of the stack

  // Debug disassembly
  Compiler.DisassembleBytecode;

  Result := Eval;

  AST.Free;
  Compiler.Free;
end;

function TEvaVM.Eval: TValue;
var
  Opcode, Op, GlobalIndex, LocalIndex, Count: Byte;
  Operand1, Operand2, Value: TValue;
  Num1, Num2: Double;
  S1, S2: String;
  Condition: Boolean;
  Address: UInt16;
begin
  while True do
    begin
      Opcode := ReadByte;
      case Opcode of
        OP_HALT:
          Exit(Pop);
        OP_CONST:
          Push(ReadConst);
        OP_ADD..OP_DIV:
          BinaryOp(Opcode);
        OP_COMPARE:
          begin
            Op := ReadByte;
            Operand2 := Pop;
            Operand1 := Pop;
            if isNum(Operand1) and isNum(Operand2) then
              begin
                Num1 := asNum(Operand1);
                Num2 := asNum(Operand2);
                Push(BoolVal(CompareValues(Op, Num1, Num2)));
              end
            else if isString(Operand1) and isString(Operand2) then
              begin
                S1 := asPasString(Operand1);
                S2 := asPasString(Operand2);
                Push(BoolVal(CompareValues(Op, S1, S2)));
              end
          end;
        OP_JUMP_IF_FALSE:
          begin
            Condition := asBool(Pop);
            Address := ReadShort;
            if not Condition then
              ip := toAddress(Address);
          end;
        OP_JUMP:
          ip := toAddress(ReadShort);
        OP_GET_GLOBAL:
          begin
            GlobalIndex := ReadByte;
            Push(Global^.get(GlobalIndex).Value);
          end;
        OP_SET_GLOBAL:
          begin
            GlobalIndex := ReadByte;
            Value := Peek(0);
            Global^.put(GlobalIndex, Value);
          end;
        OP_POP:
          Pop;
        OP_GET_LOCAL:
          begin
            LocalIndex := ReadByte;
            //if (LocalIndex < 0) or (LocalIndex >= Length(Stack)) then
            //  begin
            //    Writeln('OP_GET_LOCAL: Invalid variable index: ', LocalIndex);
            //    Halt(64);
            //  end;
            Push(bp[LocalIndex]);   // base pointer
          end;
        OP_SET_LOCAL:
          begin
            LocalIndex := ReadByte;
            Value := Peek(0);
            //if (LocalIndex < 0) or (LocalIndex >= Length(Stack)) then
            //  begin
            //    Writeln('OP_SET_LOCAL: Invalid variable index: ', LocalIndex);
            //    Halt(64);
            //  end;
            bp[LocalIndex] := Value;
          end;
        // Scope exit: clean up variables
        // note: variables sit right below the result of a block
        // so we move the result below, which will be the new top
        // after popping the variables
        OP_SCOPE_EXIT:
          begin
            Count := ReadByte;  // number of variables to pop
            // Move the result above the vars
            (sp - 1 - Count)^ := Peek(0);
            // Pop the vars
            PopN(Count);
          end;
        otherwise
          ErrorLogMsg('Unknown opcode: ' + IntToStr(Opcode));
          Halt;
      end;
    end;
end;

// Reads the current byte and advances the instruction pointer
function TEvaVM.ReadByte: Byte;
begin
  Result := ip^;
  Inc(ip);
end;

function TEvaVM.ReadShort: UInt16;
begin
  Inc(IP, 2);
  Result := (IP[-2] shl 8) or IP[-1];
end;

function TEvaVM.ReadConst: TValue;
begin
  Result := Co.Constants[ReadByte];
end;

procedure TEvaVM.Push(Value: TValue);
begin
  if sp - PValue(@Stack[0]) = cMaxStack then
    begin
      ErrorLogMsg('Stack overflow.');
      Halt;
    end;
  sp^ := Value;
  inc(sp);
end;

function TEvaVM.Pop: TValue;
begin
  if sp - PValue(@Stack[0]) = 0 then
    begin
      ErrorLogMsg('Pop(): Empty Stack.');
      Halt;
    end;
  dec(sp);
  Result := sp^;
end;

procedure TEvaVM.BinaryOp(const Op: Byte);
var
  Op1, Op2: TValue;
  s1, s2: String;
begin
  Op2 := Pop; // second operand is on the top of the stack
  Op1 := Pop; // followed by the first operand
  case Op of
    OP_ADD:
      begin
        if isNum(Op1) and isNum(Op2) then
          Push(NumVal(AsNum(Op1) + AsNum(Op2)))
        else if isString(Op1) and isString(Op2) then
          begin
            s1 := asPasString(Op1);
            s2 := asPasString(Op2);
            Push(AllocString(s1 + s2));
          end;
      end;
    OP_SUB: Push(NumVal(AsNum(Op1) - AsNum(Op2)));
    OP_MUL: Push(NumVal(AsNum(Op1) * AsNum(Op2)));
    OP_DIV: Push(NumVal(AsNum(Op1) / AsNum(Op2)));
  end;
end;

function TEvaVM.toAddress(const Index: UInt16): PByte; inline;
begin
  Result := @CO.Code.Data[Index];
end;

function TEvaVM.Peek(const OffSet: Integer): TValue;
begin
  if sp - PValue(@Stack[0]) = 0 then
    begin
      ErrorLogMsg('Peek(): Empty Stack.');
      Halt;
    end;

  Result := (sp - 1 - OffSet)^
end;

procedure TEvaVM.PopN(const Count: Integer);
begin
  if sp - PValue(@Stack[0]) = 0 then
    begin
      Writeln('PopN(): Empty Stack.');
      Halt;
    end;
  sp := sp - Count;
end;

end.

