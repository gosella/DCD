/**
 * This file is part of DCD, a development tool for the D programming language.
 * Copyright (C) 2014 Brian Schott
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module conversion.first;

import actypes;
import std.d.formatter;
import std.allocator;
import memory.allocators;
import memory.appender;
import messages;
import semantic;
import std.d.ast;
import std.d.lexer;
import std.typecons;
import stupidlog;
import containers.unrolledlist;
import string_interning;

/**
 * First Pass handles the following:
 * $(UL
 *     $(LI symbol name)
 *     $(LI symbol location)
 *     $(LI alias this locations)
 *     $(LI base class names)
 *     $(LI protection level)
 *     $(LI symbol kind)
 *     $(LI function call tip)
 *     $(LI symbol file path)
 * )
 */
final class FirstPass : ASTVisitor
{
	this(Module mod, string symbolFile, CAllocator symbolAllocator,
		CAllocator semanticAllocator)
	in
	{
		assert (symbolAllocator);
	}
	body
	{
		this.mod = mod;
		this.symbolFile = symbolFile;
		this.symbolAllocator = symbolAllocator;
		this.semanticAllocator = semanticAllocator;
	}

	void run()
	{
		visit(mod);
	}

	override void visit(const Unittest u)
	{
		// Create a dummy symbol because we don't want unit test symbols leaking
		// into the symbol they're declared in.
		SemanticSymbol* s = allocateSemanticSymbol("*unittest*",
			CompletionKind.dummy, null, 0);
		s.parent = currentSymbol;
		currentSymbol = s;
		u.accept(this);
		currentSymbol = s.parent;
	}

	override void visit(const Constructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, con.parameters, con.functionBody, con.comment);
	}

	override void visit(const SharedStaticConstructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, null, con.functionBody, con.comment);
	}

	override void visit(const StaticConstructor con)
	{
//		Log.trace(__FUNCTION__, " ", typeof(con).stringof);
		visitConstructor(con.location, null, con.functionBody, con.comment);
	}

	override void visit(const Destructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.index, des.functionBody, des.comment);
	}

	override void visit(const SharedStaticDestructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody, des.comment);
	}

	override void visit(const StaticDestructor des)
	{
//		Log.trace(__FUNCTION__, " ", typeof(des).stringof);
		visitDestructor(des.location, des.functionBody, des.comment);
	}

	override void visit(const FunctionDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof, " ", dec.name.text);
		SemanticSymbol* symbol = allocateSemanticSymbol(dec.name.text,
			CompletionKind.functionName, symbolFile, dec.name.index,
			dec.returnType);
		processParameters(symbol, dec.returnType, symbol.acSymbol.name,
			dec.parameters, dec.comment);
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = internString(dec.comment);
		currentSymbol.addChild(symbol);
		if (dec.functionBody !is null)
		{
			currentSymbol = symbol;
			dec.functionBody.accept(this);
			currentSymbol = symbol.parent;
		}
	}

	override void visit(const ClassDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.className);
	}

	override void visit(const TemplateDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.templateName);
	}

	override void visit(const InterfaceDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.interfaceName);
	}

	override void visit(const UnionDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.unionName);
	}

	override void visit(const StructDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		visitAggregateDeclaration(dec, CompletionKind.structName);
	}

	override void visit(const BaseClass bc)
	{
//		Log.trace(__FUNCTION__, " ", typeof(bc).stringof);
		currentSymbol.baseClasses.insert(iotcToStringArray(symbolAllocator,
			bc.identifierOrTemplateChain));
	}

	override void visit(const VariableDeclaration dec)
	{
		assert (currentSymbol);
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		const Type t = dec.type;
		foreach (declarator; dec.declarators)
		{
			SemanticSymbol* symbol = allocateSemanticSymbol(
				declarator.name.text, CompletionKind.variableName,
				symbolFile, declarator.name.index, t);
			symbol.protection = protection;
			symbol.parent = currentSymbol;
			symbol.acSymbol.doc = internString(dec.comment);
			currentSymbol.addChild(symbol);
		}
		if (dec.autoDeclaration !is null)
		{
			foreach (identifier; dec.autoDeclaration.identifiers)
			{
				SemanticSymbol* symbol = allocateSemanticSymbol(
					identifier.text, CompletionKind.variableName, symbolFile,
					identifier.index, null);
				symbol.protection = protection;
				symbol.parent = currentSymbol;
				symbol.acSymbol.doc = internString(dec.comment);
				currentSymbol.addChild(symbol);
			}
		}
	}

	override void visit(const AliasDeclaration aliasDeclaration)
	{
		if (aliasDeclaration.initializers.length == 0)
		{
			SemanticSymbol* symbol = allocateSemanticSymbol(
				aliasDeclaration.name.text,
				CompletionKind.aliasName,
				symbolFile,
				aliasDeclaration.name.index,
				aliasDeclaration.type);
			symbol.protection = protection;
			symbol.parent = currentSymbol;
			symbol.acSymbol.doc = internString(aliasDeclaration.comment);
			currentSymbol.addChild(symbol);
		}
		else
		{
			foreach (initializer; aliasDeclaration.initializers)
			{
				SemanticSymbol* symbol = allocateSemanticSymbol(
					initializer.name.text,
					CompletionKind.aliasName,
					symbolFile,
					initializer.name.index,
					initializer.type);
				symbol.protection = protection;
				symbol.parent = currentSymbol;
				symbol.acSymbol.doc = internString(aliasDeclaration.comment);
				currentSymbol.addChild(symbol);
			}
		}
	}

	override void visit(const AliasThisDeclaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		currentSymbol.aliasThis.insert(internString(dec.identifier.text));
	}

	override void visit(const Declaration dec)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		if (dec.attributeDeclaration !is null
			&& isProtection(dec.attributeDeclaration.attribute.attribute))
		{
			protection = dec.attributeDeclaration.attribute.attribute;
			return;
		}
		IdType p = protection;
		foreach (const Attribute attr; dec.attributes)
		{
			if (isProtection(attr.attribute))
				protection = attr.attribute;
		}
		dec.accept(this);
		protection = p;
	}

	override void visit(const Module mod)
	{
//		Log.trace(__FUNCTION__, " ", typeof(mod).stringof);
//
		currentSymbol = allocateSemanticSymbol(null, CompletionKind.moduleName,
			symbolFile);
		rootSymbol = currentSymbol;
		currentScope = allocate!Scope(semanticAllocator, 0, size_t.max);
		auto i = allocate!ImportInformation(semanticAllocator);
		i.modulePath = "object";
		i.importParts.insert("object");
		currentScope.importInformation.insert(i);
		moduleScope = currentScope;
		mod.accept(this);
		assert (currentSymbol.acSymbol.name is null);
	}

	override void visit(const EnumDeclaration dec)
	{
		assert (currentSymbol);
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		SemanticSymbol* symbol = allocateSemanticSymbol(dec.name.text,
			CompletionKind.enumName, symbolFile, dec.name.index, dec.type);
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = internString(dec.comment);
		currentSymbol = symbol;
		if (dec.enumBody !is null)
			dec.enumBody.accept(this);
		currentSymbol = symbol.parent;
		currentSymbol.addChild(symbol);
	}

	override void visit(const EnumMember member)
	{
//		Log.trace(__FUNCTION__, " ", typeof(member).stringof);
		SemanticSymbol* symbol = allocateSemanticSymbol(member.name.text,
			CompletionKind.enumMember, symbolFile, member.name.index, member.type);
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = internString(member.comment);
		currentSymbol.addChild(symbol);
	}

	override void visit(const ModuleDeclaration moduleDeclaration)
	{
//		Log.trace(__FUNCTION__, " ", typeof(dec).stringof);
		foreach (identifier; moduleDeclaration.moduleName.identifiers)
		{
			moduleName.insert(internString(identifier.text));
		}
	}

	override void visit(const StructBody structBody)
	{
//		Log.trace(__FUNCTION__, " ", typeof(structBody).stringof);
		Scope* s = allocate!Scope(semanticAllocator, structBody.startLocation, structBody.endLocation);
//		Log.trace("Added scope ", s.startLocation, " ", s.endLocation);

		ACSymbol* thisSymbol = allocate!ACSymbol(symbolAllocator, "this",
			CompletionKind.variableName, currentSymbol.acSymbol);
		thisSymbol.location = s.startLocation;
		thisSymbol.symbolFile = symbolFile;
		s.symbols.insert(thisSymbol);

		s.parent = currentScope;
		currentScope = s;
		foreach (dec; structBody.declarations)
			visit(dec);
		currentScope = s.parent;
		currentScope.children.insert(s);
	}

	override void visit(const ImportDeclaration importDeclaration)
	{
		import std.typecons;
		import std.algorithm;
//		Log.trace(__FUNCTION__, " ImportDeclaration");
		foreach (single; importDeclaration.singleImports.filter!(
			a => a !is null && a.identifierChain !is null))
		{
			auto info = allocate!ImportInformation(semanticAllocator);
			foreach (identifier; single.identifierChain.identifiers)
				info.importParts.insert(internString(identifier.text));
			info.modulePath = convertChainToImportPath(single.identifierChain);
			info.isPublic = protection == tok!"public";
			currentScope.importInformation.insert(info);
		}
		if (importDeclaration.importBindings is null) return;
		if (importDeclaration.importBindings.singleImport.identifierChain is null) return;
		auto info = allocate!ImportInformation(semanticAllocator);

		info.modulePath = convertChainToImportPath(
			importDeclaration.importBindings.singleImport.identifierChain);
		foreach (identifier; importDeclaration.importBindings.singleImport
			.identifierChain.identifiers)
		{
			info.importParts.insert(internString(identifier.text));
		}
		foreach (bind; importDeclaration.importBindings.importBinds)
		{
			Tuple!(string, string) bindTuple;
			bindTuple[0] = internString(bind.left.text);
			bindTuple[1] = bind.right == tok!"" ? null : internString(bind.right.text);
			info.importedSymbols.insert(bindTuple);
		}
		info.isPublic = protection == tok!"public";
		currentScope.importInformation.insert(info);
	}

	// Create scope for block statements
	override void visit(const BlockStatement blockStatement)
	{
//		Log.trace(__FUNCTION__, " ", typeof(blockStatement).stringof);
		Scope* s = allocate!Scope(semanticAllocator, blockStatement.startLocation,
			blockStatement.endLocation);
		s.parent = currentScope;
		currentScope.children.insert(s);

		if (currentSymbol.acSymbol.kind == CompletionKind.functionName)
		{
			foreach (child; currentSymbol.children)
			{
				if (child.acSymbol.location == size_t.max)
				{
//					Log.trace("Reassigning location of ", child.acSymbol.name);
					child.acSymbol.location = s.startLocation + 1;
				}
			}
		}
		if (blockStatement.declarationsAndStatements !is null)
		{
			currentScope = s;
			visit (blockStatement.declarationsAndStatements);
			currentScope = s.parent;
		}
	}

	override void visit(const VersionCondition versionCondition)
	{
		import std.algorithm;
		import constants;
		// TODO: This is a bit of a hack
		if (predefinedVersions.canFind(versionCondition.token.text))
			versionCondition.accept(this);
	}

	alias visit = ASTVisitor.visit;

	/// Module scope
	Scope* moduleScope;

	/// The module
	SemanticSymbol* rootSymbol;

	CAllocator symbolAllocator;

	uint symbolsAllocated;

private:

	void visitAggregateDeclaration(AggType)(AggType dec, CompletionKind kind)
	{
//		Log.trace("visiting aggregate declaration ", dec.name.text);
		if (kind == CompletionKind.unionName && dec.name == tok!"")
		{
			dec.accept(this);
			return;
		}
		SemanticSymbol* symbol = allocateSemanticSymbol(dec.name.text,
			kind, symbolFile, dec.name.index);
		if (kind == CompletionKind.className)
			symbol.acSymbol.parts.insert(classSymbols[]);
		else
			symbol.acSymbol.parts.insert(aggregateSymbols[]);
		symbol.parent = currentSymbol;
		symbol.protection = protection;
		symbol.acSymbol.doc = internString(dec.comment);
		currentSymbol = symbol;
		dec.accept(this);
		currentSymbol = symbol.parent;
		currentSymbol.addChild(symbol);
	}

	void visitConstructor(size_t location, const Parameters parameters,
		const FunctionBody functionBody, string doc)
	{
		SemanticSymbol* symbol = allocateSemanticSymbol("*constructor*",
			CompletionKind.functionName, symbolFile, location);
		processParameters(symbol, null, "this", parameters, doc);
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = internString(doc);
		currentSymbol.addChild(symbol);
		if (functionBody !is null)
		{
			currentSymbol = symbol;
			functionBody.accept(this);
			currentSymbol = symbol.parent;
		}
	}

	void visitDestructor(size_t location, const FunctionBody functionBody, string doc)
	{
		SemanticSymbol* symbol = allocateSemanticSymbol("~this",
			CompletionKind.functionName, symbolFile, location);
		symbol.acSymbol.callTip = "~this()";
		symbol.protection = protection;
		symbol.parent = currentSymbol;
		symbol.acSymbol.doc = internString(doc);
		currentSymbol.addChild(symbol);
		if (functionBody !is null)
		{
			currentSymbol = symbol;
			functionBody.accept(this);
			currentSymbol = symbol.parent;
		}
	}

	void processParameters(SemanticSymbol* symbol, const Type returnType,
		string functionName, const Parameters parameters, string doc)
	{
		if (parameters !is null)
		{
			foreach (const Parameter p; parameters.parameters)
			{
				SemanticSymbol* parameter = allocateSemanticSymbol(
					p.name.text, CompletionKind.variableName, symbolFile,
					size_t.max, p.type);
				symbol.addChild(parameter);
				parameter.parent = symbol;
			}
			if (parameters.hasVarargs)
			{
				SemanticSymbol* argptr = allocateSemanticSymbol("_argptr",
					CompletionKind.variableName, null, size_t.max, argptrType);
				argptr.parent = symbol;
				symbol.addChild(argptr);

				SemanticSymbol* arguments = allocateSemanticSymbol("_arguments",
					CompletionKind.variableName, null, size_t.max, argumentsType);
				arguments.parent = symbol;
				symbol.addChild(arguments);
			}
		}
		symbol.acSymbol.callTip = formatCallTip(returnType, functionName,
			parameters, doc);
	}

	string formatCallTip(const Type returnType, string name,
		const Parameters parameters, string doc = null)
	{
		QuickAllocator!1024 q;
		auto app = Appender!(char, typeof(q), 1024)(q);
		scope(exit) q.deallocate(app.mem);
		if (returnType !is null)
		{
			app.formatNode(returnType);
			app.put(' ');
		}
		app.put(name);
		if (parameters is null)
			app.put("()");
		else
			app.formatNode(parameters);
		return internString(cast(string) app[]);
	}

	SemanticSymbol* allocateSemanticSymbol(string name, CompletionKind kind,
		string symbolFile, size_t location = 0, const Type type = null)
	in
	{
		assert (symbolAllocator !is null);
	}
	body
	{
		ACSymbol* acSymbol = allocate!ACSymbol(symbolAllocator, name, kind);
		acSymbol.location = location;
		acSymbol.symbolFile = symbolFile;
		symbolsAllocated++;
		return allocate!SemanticSymbol(semanticAllocator, acSymbol, type);
	}

	/// Current protection type
	IdType protection;

	/// Package and module name
	UnrolledList!string moduleName;

	/// Current scope
	Scope* currentScope;

	/// Current symbol
	SemanticSymbol* currentSymbol;

	/// Path to the file being converted
	string symbolFile;

	Module mod;

	CAllocator semanticAllocator;
}

void formatNode(A, T)(ref A appender, const T node)
{
	if (node is null)
		return;
	auto f = scoped!(Formatter!(A*))(&appender);
	f.format(node);
}

private:

string[] iotcToStringArray(A)(ref A allocator, const IdentifierOrTemplateChain iotc)
{
	string[] retVal = cast(string[]) allocator.allocate((string[]).sizeof
		* iotc.identifiersOrTemplateInstances.length);
	foreach (i, ioti; iotc.identifiersOrTemplateInstances)
	{
		if (ioti.identifier != tok!"")
			retVal[i] = internString(ioti.identifier.text);
		else
			retVal[i] = internString(ioti.templateInstance.identifier.text);
	}
	return retVal;
}

static string convertChainToImportPath(const IdentifierChain ic)
{
	import std.path;
	QuickAllocator!1024 q;
	auto app = Appender!(char, typeof(q), 1024)(q);
	scope(exit) q.deallocate(app.mem);
	foreach (i, ident; ic.identifiers)
	{
		app.append(ident.text);
		if (i + 1 < ic.identifiers.length)
			app.append(dirSeparator);
	}
	return internString(cast(string) app[]);
}
