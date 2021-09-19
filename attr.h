/**********************************************
 CS415  Project 2
 Spring  2021
 Student Version
 **********************************************/

#ifndef ATTR_H
#define ATTR_H

#include <stdio.h>
#include <stdlib.h>

typedef union {
	int num;
	char *str;
} tokentype;

typedef enum type_expression {
	TYPE_INT = 0, TYPE_BOOL, TYPE_ERROR
} Type_Expression;

typedef struct {
	Type_Expression type;
	int targetRegister;
	int regIsArr;
	int label;
	int label1;
	int label2;
	int label3;
	char * str;
} regInfo;

typedef struct node {
	void * data;
	struct node * next;
} Node;

typedef struct {
	int size;
	Type_Expression type;
} Type;

#endif

