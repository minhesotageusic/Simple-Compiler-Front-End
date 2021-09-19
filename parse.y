%{
#include <stdio.h>
#include "attr.h"
#include "instrutil.h"
int yylex();
void yyerror(char * s);
#include "symtab.h"

FILE *outfile;
char *CommentBuffer;
 
%}
//need to define type here as well
%union {
		tokentype token;
        regInfo targetReg;
        char * str;
        Type raw_type;
       }

%token PROG PERIOD VAR 
%token INT BOOL PRT THEN IF DO FI ENDFOR
%token ARRAY OF 
%token BEG END ASG  
%token EQ NEQ LT LEQ GT GEQ AND OR TRUE FALSE
%token ELSE
%token FOR 
%token <token> ID ICONST 

//type define here

%type <targetReg> exp 
%type <targetReg> lhs 
%type <targetReg> ctrlexp condexp ifhead
%type <raw_type> stype 
%type <raw_type> type 
%type <str> idlist 

%start program

%nonassoc EQ NEQ LT LEQ GT GEQ 
%left '+' '-' AND
%left '*' OR

%nonassoc THEN
%nonassoc ELSE

%%
program : {
		emitComment("Assign STATIC_AREA_ADDRESS to register \"r0\"");
        emit(NOLABEL, LOADI, STATIC_AREA_ADDRESS, 0, EMPTY);} 
        PROG ID ';' block PERIOD { }
	;

block	: variables cmpdstmt { }
	;
//done
variables: /* empty */
	| VAR vardcls { }
	;
	
//done
vardcls	: vardcls vardcl ';' { }
	| vardcl ';' { }
	| error ';' { yyerror("***Error: illegal variable declaration\n");}  
	;
	
//done
vardcl	: idlist ':' type { 	//parse the idlist by the delimiter '|'
								char * token = strtok($1, "|");
								while(token != NULL){
									SymTabEntry * entry = lookup(token);
									if(entry == NULL){
										if($3.size >= 0){
											insert(token, $3.type, NextOffset($3.size), 1);
										}else{
											insert(token, $3.type, NextOffset(1), 0);
										}
									}else{
										printf("\n***Error: duplicate declaration of %s\n", token);
									}
									token = strtok(NULL, "|");
								}
						  }
	;
	
//done
idlist	:
		 idlist ',' ID { 	//add in the delimiter '|' to each string of the ID
		 					char * newStr = (char*) malloc(sizeof(char) * (strlen($1) + strlen($3.str) + 1));
		 					memcpy(newStr, $1, strlen($1));
		 					newStr[strlen($1)] = '|';
		 					memcpy(newStr + strlen($1) + 1, $3.str, strlen($3.str));
		 					$$ = newStr;
	 				   }
        | ID		{
        				$$ = (char*) malloc(sizeof(char)*strlen($1.str) + 1);
        				memcpy($$, $1.str, strlen($1.str));
         			} 
	;

//done
type	: ARRAY '[' ICONST ']' OF stype { 
											$$.type = $6.type;
											$$.size = $3.num;
										}

        | stype { $$.type = $1.type; $$.size = -1; }
	;

//done
stype	: INT { $$.type = TYPE_INT; }
        | BOOL { $$.type = TYPE_BOOL; }
	;

//done
stmtlist : stmtlist ';' stmt { }
	| stmt { }
        | error { yyerror("***Error: ';' expected or illegal statement \n");}
	;
//done
stmt    : ifstmt { }
	| fstmt { }
	| astmt { }
	| writestmt { }
	| cmpdstmt { }
	;

cmpdstmt: BEG stmtlist END { }
	;

ifstmt :  ifhead 
          THEN
          stmt {
          		int label2 = $<targetReg>1.label2;
          		int label3 = NextLabel();
          		
          		$<targetReg>1.label3 = label3;
          		
          		emit(NOLABEL, BR, label3, EMPTY, EMPTY);
          		emit(label2, NOP, EMPTY, EMPTY, EMPTY);
          }
  	  ELSE 
          stmt {
          		emit(NOLABEL, BR, $<targetReg>1.label1, EMPTY, EMPTY);
          		emit($<targetReg>1.label3, NOP, EMPTY, EMPTY, EMPTY);
          } 
          FI
	;

ifhead : IF condexp { 
						int label1 = NextLabel();
						int label2 = NextLabel();
						
						$<targetReg>$.label1 = label1;
						$<targetReg>$.label2 = label2;
						
						emit(NOLABEL, CBR, $2.targetRegister, label1, label2);
						emit(label1, NOP, EMPTY, EMPTY, EMPTY);
 					}
        ;
        
//done
writestmt: PRT '(' exp ')' { 
							 if($3.regIsArr == 1){
							 	printf("\n***Error: illegal type for write\n");
							 }
							 int printOffset = -4; /* default location for printing */
  	                         sprintf(CommentBuffer, "Code for \"PRINT\" from offset %d", printOffset);
	                         emitComment(CommentBuffer);
                                 emit(NOLABEL, STOREAI, $3.targetRegister, 0, printOffset);
                                 emit(NOLABEL, 
                                      OUTPUTAI, 
                                      0,
                                      printOffset, 
                                      EMPTY);
                               }
	;

//done
fstmt: FOR ctrlexp DO {
							int label2 = NextLabel();
							int label3 = NextLabel();
							
							$2.label2 = label2;
							$2.label3 = label3;
							
							emit(NOLABEL, CBR, $2.targetRegister, label2, label3);
							emit(label2, NOP, EMPTY, EMPTY, EMPTY);
			} stmt { 
							emit(NOLABEL, BR, $2.label1, EMPTY, EMPTY);
							emit($2.label3, NOP, EMPTY, EMPTY, EMPTY);	
					}
          ENDFOR
	;

//done
astmt : lhs ASG exp             { 
 				  if (! ((($1.type == TYPE_INT) && ($3.type == TYPE_INT)) || 
				         (($1.type == TYPE_BOOL) && ($3.type == TYPE_BOOL)))) {
				    printf("\n*** ERROR ***: Assignment types do not match.\n");
				  }
				  else{
					  if($1.regIsArr == 0) {
						  if($1.str != NULL){
							  SymTabEntry * entry = lookup($1.str);
							  if(entry != NULL){
							  	if(entry->isArray == 1){
							  		printf("\n***Error: assignment to whole array\n");
							  	}
							  	emit(NOLABEL, STOREAI, $3.targetRegister, 0, entry->offset);
							  }
						  }
					  }
					  else{
					  	emit(NOLABEL, STOREAO, $3.targetRegister, 0, $1.targetRegister); 
					  }
				  }
				  
				  
	}
	;
//done
lhs	: ID			{ 
					  //get the entry for this id
					  SymTabEntry * entry = lookup($1.str);
					  //determine if entry exist
					  if( entry == NULL ){
					  	//entry does not exist
					  	printf("\n***Error: undeclared identifier %s\n", $1.str);
					  }
					  else{
					  	//entry exist
					  	$$.type = entry->type;
					  	$$.str = entry->name;
						$$.regIsArr = 0;
					  }
				  }
	|  ID '[' exp ']' {
						if( $3.type != TYPE_INT ){
	                    	printf("\n***Error: subscript exp not type integer\n");
	                    } 
	                    SymTabEntry * entry = lookup($1.str);
	                    if(entry == NULL){
	                    	printf("\n***Error: id %s is not an array\n", $1.str);
	                    } 
	                    else {
	                    	int newReg = NextRegister();
	                    	int offset = entry->offset;
	                    	$$.type = entry->type;
	                    	$$.regIsArr = 1;
	                    	$$.targetRegister = $3.targetRegister;
	                    	//multiply $3 content by 4 (index) 
	                    	emit(NOLABEL, LOADI, 4, newReg, EMPTY);
	                    	emit(NOLABEL, MULT, newReg, $3.targetRegister, $3.targetRegister);
	                    	//add offset and array's offset
	                    	emit(NOLABEL, ADDI, $3.targetRegister, entry->offset, $3.targetRegister);                                						 
	                    }
                    }
                                ;

//done
exp	: exp '+' exp		{ int newReg = NextRegister();
                          if (! (($1.type == TYPE_INT) && ($3.type == TYPE_INT))) {
    				      	printf("\n***ERROR: Types of operands for operation + do not match.\n");
                          }
                          $$.type = $1.type;
                          $$.regIsArr = 0;
                          $$.targetRegister = newReg;
                          emit(NOLABEL, 
                          	   ADD, 
                               $1.targetRegister, 
                               $3.targetRegister, 
                               newReg);
                         }

        | exp '-' exp	{ int newReg = NextRegister();
        				  if ( !($1.type == TYPE_INT && $3.type == TYPE_INT) ){
        				  	printf("\n***ERROR: Types of operands for operation - do not match.\n");
        				  }
        				  $$.type = $1.type;
        				  $$.regIsArr = 0;
        				  $$.targetRegister = newReg;
        				  emit(NOLABEL,
        				  	   SUB,
        				  	   $1.targetRegister,
        				  	   $3.targetRegister,
        				  	   newReg);
        				 }

        | exp '*' exp	{ int newReg = NextRegister();
        				  if ( !($1.type == TYPE_INT && $3.type == TYPE_INT) ){
        				  	printf("\n***ERROR: Types of operands for operation * do not match.\n");
        				  }
        				  $$.type = $1.type;
        				  $$.regIsArr = 0;
        				  $$.targetRegister = newReg;
        				  emit(NOLABEL,
        				  	   MULT,
        				  	   $1.targetRegister,
        				  	   $3.targetRegister,
        				  	   newReg);
        				 }

        | exp AND exp	{ int newReg = NextRegister();
        				  if ( !($1.type == TYPE_BOOL && $3.type == TYPE_BOOL) ){
        				  	printf("\n***ERROR: Types of operands for operation AND do not match.\n");
        				  }
        				  $$.type = $1.type;
        				  $$.regIsArr = 0;
        				  $$.targetRegister = newReg;
        				  emit(NOLABEL,
        				  	   AND_INSTR,
        				  	   $1.targetRegister,
        				  	   $3.targetRegister,
        				  	   newReg);
        				 }


        | exp OR exp    { int newReg = NextRegister();
        				  if ( !($1.type == TYPE_BOOL && $3.type == TYPE_BOOL) ){
        				  	printf("\n***ERROR: Types of operands for operation OR do not match.\n");
        				  }
        				  $$.type = $1.type;
        				  $$.regIsArr = 0;
        				  $$.targetRegister = newReg;
        				  emit(NOLABEL,
        				  	   OR_INSTR,
        				  	   $1.targetRegister,
        				  	   $3.targetRegister,
        				  	   newReg);
        				 }


        | ID			{ 
	                          int newReg = NextRegister();
	                          SymTabEntry * entry = lookup($1.str);
	                          if ( entry == NULL ) {
	                          	  printf("\n***Error: undeclared identifier %s\n", $1.str);
	                          }else{
	                              int offset = entry->offset;
		                          
		                          $$.targetRegister = newReg;
		                          $$.regIsArr = 0;
		                          if(entry->isArray == 1) $$.regIsArr = 1;
								  $$.type = entry->type;
								  
								  emit(NOLABEL, LOADAI, 0, offset, newReg);
                              }
	                        }

        | ID '[' exp ']' { 
        				   SymTabEntry * entry = lookup($1.str);
        				   //check inner expression is type int
        				   if ( !($3.type == TYPE_INT) ){
        				   		printf("\n***Error: subscript exp not type integer\n");
        				   }
        				   //check if ID is declared
        				   if( entry == NULL ){
        				   		printf("\n***Error: id %s is not an array\n", $1.str);
        				   }
        				   else {
        				   	   int newReg = NextRegister();
        				   	   int newReg2 = NextRegister();
        				   	   //multiply exp by unit of integer (4)
        				   	   emit(NOLABEL, LOADI, 4, newReg, EMPTY);
        				   	   emit(NOLABEL, MULT, newReg, $3.targetRegister, $3.targetRegister);
        				   	   //add array's offset to exp
	        				   emit(NOLABEL, ADDI, $3.targetRegister, entry->offset, $3.targetRegister);
	        				   
	        				   $$.type = entry->type;
	        				   $$.regIsArr = 0;
	        				   $$.targetRegister = newReg2;
	        				   
	        				   //load content from memory to new register
	        				   emit(NOLABEL, LOADAO, 0, $3.targetRegister, newReg2);
	        			   }   				   
           				 }
 


	| ICONST                 { int newReg = NextRegister();
	                           $$.targetRegister = newReg;
	                           $$.regIsArr = 0;
				   $$.type = TYPE_INT;
				   emit(NOLABEL, LOADI, $1.num, newReg, EMPTY); }

        | TRUE                   { int newReg = NextRegister(); /* TRUE is encoded as value '1' */
	                           $$.targetRegister = newReg;
	                           $$.regIsArr = 0;
				   $$.type = TYPE_BOOL;
				   emit(NOLABEL, LOADI, 1, newReg, EMPTY); }

        | FALSE                   { int newReg = NextRegister(); /* TRUE is encoded as value '0' */
	                           $$.targetRegister = newReg;
	                           $$.regIsArr = 0;
				   $$.type = TYPE_BOOL;
				   emit(NOLABEL, LOADI, 0, newReg, EMPTY); }

	| error { yyerror("***Error: illegal expression\n");}  
	;

//done
ctrlexp	: ID ASG ICONST ',' ICONST {
 								   	SymTabEntry * entry = lookup($1.str);
 								   	//test if ID exist
 								   	if ( entry == NULL ){
 								   		//id does not exist error
 								   		printf("\n***Error: undeclared identifier %s\n", $1.str);
 								   	}else{
 								   		
 								   		if($3.num > $5.num){
 								   			printf("\n***Error: lower bound exceeds upper bound\n");
 								   		}
 								   		
 								   		if(entry->isArray == 1 || entry->type == TYPE_BOOL){
 								   			printf("\n***Error: induction variable not scalar integer variable\n");
 								   		}
 								   		
 								   		int newReg = NextRegister();
 								   		int newReg2 = NextRegister();
 								   		int newReg3 = NextRegister();
 								   		int newReg4 = NextRegister();
 								   		int newReg5 = NextRegister();
 								   		int newReg6 = NextRegister();
 								   		int newReg7 = NextRegister();
 								   		//make label to jump back								   		
 								   		int label = NextLabel();
 								   		
 								   		$$.type = TYPE_BOOL;
 								   		$$.label1 = label;
 								   		$$.targetRegister = newReg7;
 								   		
 								   		//load in value 1
 								   		emit(NOLABEL, LOADI, 1, newReg, EMPTY);
 								   		//load in first constant
 								   		emit(NOLABEL, LOADI, $3.num, newReg2, EMPTY);
 								   		//subtract by 1
 								   		emit(NOLABEL, SUB, newReg2, newReg, newReg3);
 								   		//store result into id
 								   		emit(NOLABEL, STOREAI, newReg3, 0, entry->offset);
 								   		//mark label
 								   		emit(label, NOP, EMPTY, EMPTY, EMPTY);
 								   		//load in value from id to temp reg
 								   		emit(NOLABEL, LOADAI, 0, entry->offset, newReg4);
 								   		//add to value by 1
 								   		emit(NOLABEL, ADD, newReg, newReg4, newReg5);
 								   		//store result into id
 								   		emit(NOLABEL, STOREAI, newReg5, 0, entry->offset);
 								   		//load in second constant
 								   		emit(NOLABEL, LOADI, $5.num, newReg6, EMPTY);
 								   		//compare id and second constant
 								   		emit(NOLABEL, CMPLE, newReg5, newReg6, newReg7);
 								   	}
 								   }
        ;

//done
condexp	: exp NEQ exp		{ 
								int newReg = NextRegister();
								if ( $1.type != $3.type ) {
									printf("\n***Error: types of operands for operation '!=' do not match\n");
								}
								
								$$.targetRegister = newReg;
								$<targetReg>$.type = TYPE_BOOL;
								
								emit(NOLABEL, 
									CMPNE, 
									$1.targetRegister, 
									$3.targetRegister, 
									newReg);
							} 

        | exp EQ exp		{  
        						int newReg = NextRegister();
        						if( $1.type != $3.type ){
        							printf("\n***Error: types of operands for operation '==' do not match\n");
        						}
        						
        						$$.targetRegister = newReg;
        						$<targetReg>$.type = TYPE_BOOL;
        						
								emit(NOLABEL, 
									CMPEQ, 
									$1.targetRegister, 
									$3.targetRegister, 
									newReg);
        					} 

        | exp LT exp		{  
        						int newReg = NextRegister();
        						if( !($1.type == TYPE_INT && $3.type == TYPE_INT) ){
        							printf("\n***ERROR: Operator types must be integer.\n");
        						}
        						
        						$$.targetRegister = newReg;
        						$<targetReg>$.type = TYPE_BOOL;
        						
								emit(NOLABEL, 
									CMPLT, 
									$1.targetRegister, 
									$3.targetRegister, 
									newReg);
        					} 

        | exp LEQ exp		{  
        						int newReg = NextRegister();
        						if( !($1.type == TYPE_INT && $3.type == TYPE_INT) ){
        							//is the operation correct???
        							printf("\n***ERROR: Operator types must be integer.\n");
        						}
        						
        						$$.targetRegister = newReg;
        						$<targetReg>$.type = TYPE_BOOL;
        						
								emit(NOLABEL, 
									CMPLE, 
									$1.targetRegister, 
									$3.targetRegister, 
									newReg);
        					} 

	| exp GT exp		{  
        						int newReg = NextRegister();
        						if( !($1.type == TYPE_INT && $3.type == TYPE_INT) ){
        							//is the operation correct???
        							printf("\n***ERROR: Operator types must be integer.\n");
        						}
        						
        						$$.targetRegister = newReg;
        						$<targetReg>$.type = TYPE_BOOL;
        						
								emit(NOLABEL, 
									CMPGT, 
									$1.targetRegister, 
									$3.targetRegister, 
									newReg);
        					}

	| exp GEQ exp		{  
        						int newReg = NextRegister();
        						if( !($1.type == TYPE_INT && $3.type == TYPE_INT) ){
        							//is the operation correct???
        							printf("\n***ERROR: Operator types must be integer.\n");
        						}
        						
        						$$.targetRegister = newReg;
        						$<targetReg>$.type = TYPE_BOOL;
        						
								emit(NOLABEL, 
									CMPGE, 
									$1.targetRegister, 
									$3.targetRegister, 
									newReg);
        					}

	| error { yyerror("***Error: illegal conditional expression\n");}  
        ;

%%

void yyerror(char* s) {
        fprintf(stderr,"%s\n",s);
        }


int
main(int argc, char* argv[]) {

  printf("\n     CS415 Spring 2021 Compiler\n\n");

  outfile = fopen("iloc.out", "w");
  if (outfile == NULL) { 
    printf("ERROR: Cannot open output file \"iloc.out\".\n");
    return -1;
  }

  CommentBuffer = (char *) malloc(1832);  
  InitSymbolTable();

  printf("1\t");
  yyparse();
  printf("\n");

  PrintSymbolTable();
  
  fclose(outfile);
  
  return 1;
}




