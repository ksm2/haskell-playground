module MetroLang.Parser (parseString, parseFile) where

import Control.Monad (liftM)
import Data.Functor.Identity
import Text.ParserCombinators.Parsec
import Text.ParserCombinators.Parsec.Expr
import Text.ParserCombinators.Parsec.Language
import qualified Text.ParserCombinators.Parsec.Token as Token
import MetroLang.AST

languageDef :: GenLanguageDef String u Identity
languageDef =
  emptyDef { Token.commentStart    = "/*"
           , Token.commentEnd      = "*/"
           , Token.commentLine     = "//"
           , Token.identStart      = letter <|> oneOf "_"
           , Token.identLetter     = alphaNum <|> oneOf "_"
           , Token.reservedNames   = [ "class"
                                     , "else"
                                     , "enum"
                                     , "extends"
                                     , "false"
                                     , "fn"
                                     , "for"
                                     , "if"
                                     , "impl"
                                     , "import"
                                     , "interface"
                                     , "null"
                                     , "return"
                                     , "this"
                                     , "true"
                                     ]
           , Token.reservedOpNames = [ ","
                                     , "."
                                     , "?."
                                     , "("
                                     , ")"
                                     , "{"
                                     , "}"
                                     , "or"
                                     , "and"
                                     , "not"
                                     , "is"
                                     , "+"
                                     , "-"
                                     , "*"
                                     , "/"
                                     , "%"
                                     , "="
                                     , "=="
                                     , "!="
                                     , ">="
                                     , ">"
                                     , "<"
                                     ]
           }

lexer       :: Token.GenTokenParser String u Identity
lexer       = Token.makeTokenParser languageDef

identifier  :: Parser Identifier
identifier  = Token.identifier lexer

-- | reserved parses a reserved word
reserved    :: String -> Parser ()
reserved    = Token.reserved lexer

-- | reservedOp parses an operator
reservedOp  :: String -> Parser ()
reservedOp  = Token.reservedOp lexer

-- | symbol parses a symbol with trailing whitespace
symbol  :: String -> Parser String
symbol  = Token.symbol lexer

-- | parens parses round brackets ("(" and ")") around an expression
parens      :: Parser a -> Parser a
parens      = Token.parens     lexer

-- | braces parses curly brackets ("{" and "}") around an expression
braces      :: Parser a -> Parser a
braces      = Token.braces     lexer

-- | angles parses angle brackets ("<" and ">") around an expression
angles      :: Parser a -> Parser a
angles      = Token.angles     lexer

-- | integer parses an integer
integer     :: Parser Integer
integer     = Token.integer lexer

-- | whiteSpace parses whitespace
whiteSpace  :: Parser ()
whiteSpace  = Token.whiteSpace lexer

comma :: Parser ()
comma = symbol "," >> return ()
commaSep :: Parser a -> Parser [a]
commaSep a = sepBy a comma
commaSepEnd :: Parser a -> Parser [a]
commaSepEnd a = sepEndBy a comma

whileParser :: Parser Module
whileParser = whiteSpace >> moduleParser

moduleParser :: Parser Module
moduleParser =
  do  values <- many declaration
      return $ Mod values

declaration :: Parser Declaration
declaration =   importDeclaration
            <|> enumDeclaration
            <|> interfaceDeclaration
            <|> classDeclaration
            <|> implDeclaration
            <|> funcDeclaration

importDeclaration :: Parser Declaration
importDeclaration =
  do  reserved "import"
      moduleName <- stringLiteral
      specifier <- importSpecifier
      return $ Import moduleName specifier

enumDeclaration :: Parser Declaration
enumDeclaration =
  do  reserved "enum"
      name <- identifier
      args <- typeArgs
      items <- braces enumItems
      return $ Enumeration name args items

interfaceDeclaration :: Parser Declaration
interfaceDeclaration =
  do  reserved "interface"
      name <- identifier
      args <- typeArgs
      extends <- interfaceExtends
      body <- interfaceBlock
      return $ Interface name args extends body

classDeclaration :: Parser Declaration
classDeclaration =
  do  reserved "class"
      name <- identifier
      args <- typeArgs
      pars <- params
      extends <- classExtends
      implements <- impls
      body <- classBlock
      return $ Class name args pars extends implements body

implDeclaration :: Parser Declaration
implDeclaration =
  do  reserved "impl"
      interfaceType <- typeParser
      reserved "for"
      targetType <- typeParser
      body <- classBlock
      return $ Impl interfaceType targetType body

funcDeclaration :: Parser Declaration
funcDeclaration =
  do  reserved "fn"
      fnName <- identifier
      fnParams <- params
      fnReturn <- returnType
      body <- block
      return $ Func fnName fnParams fnReturn body

optionalParams :: Parser Params
optionalParams = option [] params

params :: Parser Params
params = parens commaSeparatedParams

commaSeparatedParams :: Parser Params
commaSeparatedParams = commaSepEnd param

param :: Parser Param
param =
  do  name <- identifier
      paramType <- typeParser
      return $ Par name paramType

returnType :: Parser ReturnType
returnType = option TVoid typeParser

importSpecifier :: Parser ImportSpecifier
importSpecifier = funcImportSpecifier

funcImportSpecifier :: Parser ImportSpecifier
funcImportSpecifier =
  do  reserved "fn"
      fnName <- identifier
      fnParams <- params
      fnReturn <- returnType
      return $ FuncImport fnName fnParams fnReturn

enumItems :: Parser [EnumItem]
enumItems = many enumItem

enumItem :: Parser EnumItem
enumItem =
  do  itemName <- identifier
      itemParams <- optionalParams
      return $ EnumItem itemName itemParams

interfaceExtends :: Parser InterfaceExtends
interfaceExtends = option [] $ reserved "extends" >> (commaSep typeParser)

interfaceBlock :: Parser InterfaceBlock
interfaceBlock = liftM InterfaceBlock $ braces $ many methodSignature

classExtends :: Parser ClassExtends
classExtends = option TVoid $ reserved "extends" >> typeParser

impls :: Parser Implements
impls = option [] $ reserved "impl" >> (commaSep typeParser)

classBlock :: Parser ClassBlock
classBlock = liftM ClassBlock $ braces $ many method

methodSignature :: Parser MethodSignature
methodSignature =
  do  methodName <- identifier
      methodParams <- params
      methodReturn <- returnType
      return $ MethodSignature methodName methodParams methodReturn

method :: Parser Method
method =
  do  signature <- methodSignature
      body <- block
      return $ Method signature body

block :: Parser Block
block = liftM Block $ braces (many stmt)

stmt :: Parser Stmt
stmt =   liftM IfStmt ifParser
     <|> liftM ReturnStmt returnStmt
     <|> liftM ExprStmt expr

ifParser :: Parser If
ifParser =
  do  reserved "if"
      cond <- expr
      thenBlock <- block
      e <- optionMaybe elseParser
      return $ If cond thenBlock e

elseParser :: Parser Else
elseParser =
  do  reserved "else"
      (liftM ElseIfStmt ifParser) <|> (liftM ElseStmt block)

returnStmt :: Parser Expression
returnStmt =
  do  reserved "return"
      expr

expr :: Parser Expression
expr = buildExpressionParser operators term

operators :: [[Operator Char () Expression]]
operators = [ [Infix  (reservedOp "."   >> return (Binary Chain               )) AssocLeft,
               Infix  (reservedOp "?."  >> return (Binary OptChain            )) AssocLeft]
            , [Prefix (reservedOp "-"   >> return (Unary  Neg                 ))          ]
            , [Prefix (reservedOp "not" >> return (Unary  LogicalNot          ))          ]
            , [Infix  (reservedOp "*"   >> return (Binary Multiply            )) AssocLeft,
               Infix  (reservedOp "/"   >> return (Binary Divide              )) AssocLeft,
               Infix  (reservedOp "%"   >> return (Binary Modulo              )) AssocLeft]
            , [Infix  (reservedOp "+"   >> return (Binary Add                 )) AssocLeft,
               Infix  (reservedOp "-"   >> return (Binary Subtract            )) AssocLeft]
            , [Infix  (reservedOp "and" >> return (Binary LogicalAnd          )) AssocLeft,
               Infix  (reservedOp "or"  >> return (Binary LogicalOr           )) AssocLeft]
            , [Infix  (reservedOp "<"   >> return (Binary LessThan            )) AssocLeft,
               Infix  (reservedOp "<="  >> return (Binary LessThanOrEqual     )) AssocLeft,
               Infix  (reservedOp ">"   >> return (Binary GreaterThan         )) AssocLeft,
               Infix  (reservedOp ">="  >> return (Binary GreaterThanOrEqual  )) AssocLeft]
            , [Infix  (reservedOp "=="  >> return (Binary Equal               )) AssocLeft,
               Infix  (reservedOp "!="  >> return (Binary Unequal             )) AssocLeft,
               Infix  (reservedOp "is"  >> return (Binary Is                  )) AssocLeft]
            , [Infix  (reservedOp ":="  >> return (Binary Definition          )) AssocLeft,
               Infix  (reservedOp "="   >> return (Binary Assignment          )) AssocLeft]
            ]

term :: Parser Expression
term =   parens expr
     <|> nullLiteral
     <|> thisKeyword
     <|> liftM BooleanLiteral booleanLiteral
     <|> try callExpr
     <|> liftM VariableExpr identifier
     <|> liftM NumberLiteral integer
     <|> liftM StringLiteral stringLiteral

callExpr :: Parser Expression
callExpr =
  do  callee <- identifier
      arg <- arguments
      return $ Call callee arg

arguments :: Parser Arguments
arguments = liftM Args $ parens (commaSepEnd expr)

booleanLiteral :: Parser Bool
booleanLiteral =   (reserved "true" >> (return True))
               <|> (reserved "false" >> (return False))

stringLiteral :: Parser String
stringLiteral =
  do  _ <- oneOf "\""
      stringValue <- many (noneOf "\"")
      _ <- oneOf "\""
      whiteSpace
      return $ decodeStringLiteral stringValue

decodeStringLiteral :: String -> String
decodeStringLiteral [] = []
decodeStringLiteral ('\\':'t':xs) = (toEnum 9):(decodeStringLiteral xs)
decodeStringLiteral ('\\':'n':xs) = (toEnum 10):(decodeStringLiteral xs)
decodeStringLiteral ('\\':'r':xs) = (toEnum 13):(decodeStringLiteral xs)
decodeStringLiteral ('\\':'e':xs) = (toEnum 27):(decodeStringLiteral xs)
decodeStringLiteral (x:xs) = x:(decodeStringLiteral xs)

nullLiteral :: Parser Expression
nullLiteral = reserved "null" >> (return NullLiteral)

thisKeyword :: Parser Expression
thisKeyword = reserved "this" >> (return ThisKeyword)

typeArgs :: Parser TypeArgs
typeArgs = option [] $ angles $ many typeParser

typeParser :: Parser Type
typeParser = primitiveType <|> genericType

primitiveType :: Parser Type
primitiveType =
  do  name <- primitiveTypeName
      return $ Primitive name

primitiveTypeName :: Parser PrimitiveType
primitiveTypeName =
      (reserved "Bool" >> return TBool)
  <|> (reserved "Byte" >> return TByte)
  <|> (reserved "UByte" >> return TUByte)
  <|> (reserved "Int" >> return TInt)
  <|> (reserved "UInt" >> return TUInt)
  <|> (reserved "Long" >> return TLong)
  <|> (reserved "ULong" >> return TULong)
  <|> (reserved "Float" >> return TFloat)
  <|> (reserved "Double" >> return TDouble)
  <|> (reserved "String" >> return TString)

genericType :: Parser Type
genericType =
  do  name <- identifier
      args <- typeArgs
      return $ Generic name args

parseString :: String -> Module
parseString str =
  case parse whileParser "" str of
    Left e  -> error $ show e
    Right r -> r

parseFile :: String -> IO Module
parseFile file =
  do program  <- readFile file
     case parse whileParser "" program of
       Left e  -> print e >> fail "parse error"
       Right r -> return r
