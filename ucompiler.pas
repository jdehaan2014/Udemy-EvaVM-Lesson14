unit uCompiler;

{$mode ObjFPC}{$H+}
{$ModeSwitch advancedrecords}
{$ModeSwitch implicitfunctionspecialization}

interface

uses
  SysUtils, uAST, uValue, Generics.Collections, uDisassembler, uGlobals;

type

  TCompareOps = specialize TDictionary<String, Byte>;

  TCompiler = record
    public
      CO: TCodeObj;
      Global: PGlobal;
      procedure Init(AGlobal: PGlobal);
      procedure Free;
      function Compile(Expr: TExpr): TCodeObj;
      procedure Gen(Expr: TExpr);
      procedure DisassembleBytecode;
    private
      CompareOps: TCompareOps; // map of strings and compare operators
      Disassembler: TDisassembler;
      procedure Emit(Code: Byte);
      function NumericConstIdx(const Value: Double): Integer;
      function StringConstIdx(const Value: String): Integer;
      function BooleanConstIdx(const Value: Boolean): Integer;
      procedure GenBinaryOp(const Op: Byte; Expr1, Expr2: TExpr);
      function getOffSet: Integer;
      procedure writeByteAtOffSet(OffSet: Integer; Value: Byte);
      procedure patchJumpAddress(OffSet: Integer; Value: UInt16);
      procedure ScopeEnter;
      procedure ScopeExit;
      function isGlobalScope: Boolean;
      function isDeclaration(Expr: TExpr): Boolean;
      function isVarDeclaration(Expr: TExpr): Boolean;
      function isTaggedList(Expr: TExpr; const Tag: ShortString): Boolean;
      function getVarsCountOnScopeExit: Integer;
  end;

implementation
uses uOpcodes;

{ TCompiler }

procedure TCompiler.Init(AGlobal: PGlobal);
begin
  Global := AGlobal;

  CompareOps := TCompareOps.Create;
  CompareOps.Add('<', 0);
  CompareOps.Add('>', 1);
  CompareOps.Add('=', 2);
  CompareOps.Add('>=', 3);
  CompareOps.Add('<=', 4);
  CompareOps.Add('<>', 5);
end;

procedure TCompiler.Free;
begin
  CompareOps.Free;
  CO.Free;
end;

function TCompiler.Compile(Expr: TExpr): TCodeObj;
begin
  CO := asCode(AllocCode('main'));
  // Generate recursively from top-level
  Gen(Expr);

  // Explicitly VM-stop marker
  Emit(OP_HALT);

  Result := CO;
end;

// Main compile loop
procedure TCompiler.Gen(Expr: TExpr);
var
  Tag: TExpr;
  Op, VarName: String;
  elseJmpAddr, elseBranchAddr, endAddr, endBranchAddr, GlobalIndex, i,
    LocalIndex: Integer;
  isLast, isLocalDecl: Boolean;
begin
  case Expr.Typ of
    etNumber:
      begin
        Emit(OP_CONST);
        Emit(NumericConstIdx(Expr.Num));
      end;
    etString:
      begin
        Emit(OP_CONST);
        Emit(StringConstIdx(Expr.Str));
      end;
    etSymbol:  // variables, operators
      begin
        // Booleans
        if (Expr.Str = 'true') or (Expr.Str = 'false') then
          begin
            Emit(OP_CONST);
            Emit(BooleanConstIdx(IfThen(Expr.Str = 'true', True, False)));
          end
        else // variables:
          begin
            VarName := Expr.Str;

            // 1. Local vars
            LocalIndex := CO.getLocalIndex(VarName);
            if LocalIndex <> -1 then
              begin
                Emit(OP_GET_LOCAL);
                Emit(LocalIndex);
              end
            else
              begin
                // 2. Global variables
                if not Global^.Exists(VarName) then
                  begin
                    Writeln('[Compiler]: Reference error: ', VarName);
                    Halt(76);
                  end;
                Emit(OP_GET_GLOBAL);
                Emit(Global^.getGlobalIndex(VarName));
              end;
          end
      end;
    etList:
      begin
        Tag := Expr.List[0];
        if Tag.Typ = etSymbol then
          begin
            Op := Tag.Str;
            // Binary operations
            if Op = '+' then
              GenBinaryOp(OP_ADD, Expr.List[1], Expr.List[2])
            else if Op = '-' then
              GenBinaryOp(OP_SUB, Expr.List[1], Expr.List[2])
            else if Op = '*' then
              GenBinaryOp(OP_MUL, Expr.List[1], Expr.List[2])
            else if Op = '/' then
              GenBinaryOp(OP_DIV, Expr.List[1], Expr.List[2])
            // Compare operations
            else if CompareOps.ContainsKey(Op) then
              begin
                Gen(Expr.List[1]);
                Gen(Expr.List[2]);
                Emit(OP_COMPARE);
                Emit(CompareOps[Op]);
              end
            // if expr: (if <test> <consequent> <alternate>
            else if Op = 'if' then
              begin
                Gen(Expr.List[1]); // test condition
                Emit(OP_JUMP_IF_FALSE);

                // Else branch. Init with 0 address, will be patched, 2 bytes
                Emit(0);
                Emit(0);
                elseJmpAddr := getOffset - 2;

                Gen(Expr.List[2]); // consequent part
                Emit(OP_JUMP);
                // place holder
                Emit(0);
                Emit(0);
                endAddr := getOffset - 2;

                elseBranchAddr := getOffset;
                patchJumpAddress(elseJmpAddr, elseBranchAddr);

                // alternate part if we have it
                if Expr.List.Count = 4 then
                  Gen(Expr.List[3]);

                endBranchAddr := getOffSet;
                patchJumpAddress(endAddr, endBranchAddr);
              end
            else if Op = 'var' then
              // Variable decl: ( var x (+ y 10) )
              begin
                VarName := Expr.List[1].Str;
                Gen(Expr.List[2]);
                if isGlobalScope then             // 1. Global vars
                  begin
                    Global^.Define(VarName);
                    Emit(OP_SET_GLOBAL);
                    Emit(Global^.getGlobalIndex(VarName));
                  end
                else // 2. Local vars
                  begin
                    CO.addLocal(VarName);
                    Emit(OP_SET_LOCAL);
                    Emit(CO.getLocalIndex(VarName));
                  end;
              end
            else if Op = 'set' then
              // Variable assignment: ( set x (+ y 10) )
              begin
                VarName := Expr.List[1].Str;
                // assignment value
                Gen(Expr.List[2]);

                LocalIndex := CO.getLocalIndex(VarName);
                if LocalIndex <> -1 then   // 2. Local vars first
                  begin
                    Emit(OP_SET_LOCAL);
                    Emit(LocalIndex);
                  end
                else
                  begin   // 1. Global vars
                    GlobalIndex := Global^.getGlobalIndex(VarName);
                    if GlobalIndex = -1 then
                      begin
                        Writeln('[Compiler]: Reference error: ', VarName, ' is not defined.');
                        Halt(77);
                      end;
                      Emit(OP_SET_GLOBAL);
                      Emit(GlobalIndex);
                  end;
              end
            else if Op = 'begin' then // blocks
              begin
                ScopeEnter;
                // compile each expression inside the block
                for i := 1 to Expr.List.Count - 1 do
                  begin
                    // Value of last expression is kept on the stack
                    isLast := i = Expr.List.Count - 1;
                    // Local variable or function should not Pop
                    isLocalDecl := isDeclaration(Expr.List[i]) and (not isGlobalScope);
                    Gen(Expr.List[i]);  // Generate expression code
                    if (not isLast) and (not isLocalDecl) then
                      Emit(OP_POP);
                  end;

                ScopeExit;
              end
          end;
      end;
  end;
end;

procedure TCompiler.DisassembleBytecode;
begin
  Disassembler.Init(Global);
  Disassembler.Disassemble(CO);
end;

procedure TCompiler.Emit(Code: Byte);
begin
  CO.Code.Add(Code);
end;

function TCompiler.NumericConstIdx(const Value: Double): Integer;
var
  i: Integer;
begin
  for i:=0 to CO.Constants.Count - 1 do
    begin
      if not isNum(CO.Constants[i]) then
        Continue;
      if asNum(CO.Constants[i]) = Value then
        Exit(i);
    end;
  CO.Constants.Add(NumVal(Value));
  Result := CO.Constants.Count - 1;
end;

function TCompiler.StringConstIdx(const Value: String): Integer;
var
  i: Integer;
begin
  for i:=0 to CO.Constants.Count - 1 do
    begin
      if not isString(CO.Constants[i]) then
        Continue;
      if asPasString(CO.Constants[i]) = Value then
        Exit(i);
    end;
  CO.Constants.Add(AllocString(Value));
  Result := CO.Constants.Count - 1;
end;

function TCompiler.BooleanConstIdx(const Value: Boolean): Integer;
var
  i: Integer;
begin
  for i:=0 to CO.Constants.Count - 1 do
    begin
      if not isBool(CO.Constants[i]) then
        Continue;
      if asBool(CO.Constants[i]) = Value then
        Exit(i);
    end;
  CO.Constants.Add(BoolVal(Value));
  Result := CO.Constants.Count - 1;
end;

procedure TCompiler.GenBinaryOp(const Op: Byte; Expr1, Expr2: TExpr);
begin
  Gen(Expr1);
  Gen(Expr2);
  Emit(Op);
end;

function TCompiler.getOffSet: Integer;
begin
  Result := CO.Code.Count;
end;

procedure TCompiler.writeByteAtOffSet(OffSet: Integer; Value: Byte);
begin
  CO.Code[OffSet] := Value;
end;

procedure TCompiler.patchJumpAddress(OffSet: Integer; Value: UInt16);
begin
  writeByteAtOffSet(OffSet, (Value shr 8) and $ff);
  writeByteAtOffSet(OffSet + 1, Value and $ff);
end;

procedure TCompiler.ScopeEnter;
begin
  // Increment scope level when entering a new scope
  Inc(CO.ScopeLevel);
end;

procedure TCompiler.ScopeExit;
var
  VarsCount: Byte;
begin
  // Pop variables from the stack if declared in this scope
  VarsCount := getVarsCountOnScopeExit;
  if VarsCount > 0 then
    begin
      Emit(OP_SCOPE_EXIT);
      Emit(VarsCount);
    end;

  Dec(CO.ScopeLevel);
end;

function TCompiler.isGlobalScope: Boolean;
begin
  Result := (CO.Name = 'main') and (CO.ScopeLevel = 1);
end;

function TCompiler.isDeclaration(Expr: TExpr): Boolean;
begin
  Result := isVarDeclaration(Expr);
end;

function TCompiler.isVarDeclaration(Expr: TExpr): Boolean;
begin
  Result := isTaggedList(Expr, 'var');
end;

function TCompiler.isTaggedList(Expr: TExpr; const Tag: ShortString): Boolean;
begin
  Result := (Expr.Typ = etList) and
            (Expr.List[0].Typ = etSymbol) and
            (Expr.List[0].Str = Tag);
end;

function TCompiler.getVarsCountOnScopeExit: Integer;
begin
  Result := 0;
  if CO.Locals.Count > 0 then
    while (CO.Locals.Count > 0) and (CO.Locals.Last.ScopeLevel = CO.ScopeLevel) do
      begin
        CO.Locals.Delete(CO.Locals.Count-1);
        Inc(Result);
      end;
    //while (CO.Locals.Count > 0) and (CO.Locals.Last.ScopeLevel = CO.ScopeLevel) do
    //  begin
    //    CO.Locals.Remove(CO.Locals.Last);
    //    Inc(Result);
    //  end;
end;


end.

