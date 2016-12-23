// Written in the D programming language
// License: http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0

import std.array, std.algorithm, std.conv;
import std.functional, std.range;
import expression, declaration, util;

bool compatible(Expression lhs,Expression rhs){
	return lhs.eval() == rhs.eval();
}


class Type: Expression{
	this(){ if(!this.type) this.type=typeTy; sstate=SemState.completed; }
	override @property string kind(){ return "type"; }
	override string toString(){ return "T"; }
	abstract override bool opEquals(Object r);
}

class ErrorTy: Type{
	this(){}//{sstate = SemState.error;}
	override string toString(){return "__error";}
	mixin VariableFree;
}


class ℝTy: Type{
	private this(){}
	override string toString(){
		return "ℝ";
	}
	override bool opEquals(Object o){
		return !!cast(ℝTy)o;
	}
	mixin VariableFree;
}
private ℝTy theℝ;

ℝTy ℝ(){ return theℝ?theℝ:(theℝ=new ℝTy()); }

class AggregateTy: Type{
	DatDecl decl;
	this(DatDecl decl){
		this.decl=decl;
	}
	override bool opEquals(Object o){
		if(auto r=cast(AggregateTy)o)
			return decl is r.decl;
		return false;
	}
	override string toString(){
		return decl.name.name;
	}
	mixin VariableFree;
}

class ContextTy: Type{
	private this(){} // dummy
	override bool opEquals(Object o){
		return !!cast(ContextTy)o;
	}
	mixin VariableFree;
}
private ContextTy theContextTy;
ContextTy contextTy(){ return theContextTy?theContextTy:(theContextTy=new ContextTy()); }



class TupleTy: Type{
	Expression[] types;
	private this(Expression[] types)in{
		assert(types.all!(x=>x.type==typeTy));
	}body{
		this.types=types;
	}
	override string toString(){
		if(!types.length) return "𝟙";
		if(types.length==1) return "("~types[0].toString()~")¹";
		string addp(Expression a){
			if(cast(FunTy)a) return "("~a.toString()~")";
			return a.toString();
		}
		return types.map!(a=>cast(TupleTy)a&&a!is unit?"("~a.toString()~")":addp(a)).join(" × ");
	}
	override int freeVarsImpl(scope int delegate(string) dg){
		foreach(t;types)
			if(auto r=t.freeVarsImpl(dg))
				return r;
		return 0;
	}
	override TupleTy substituteImpl(Expression[string] subst){
		auto ntypes=types.dup;
		foreach(ref t;ntypes) t=t.substitute(subst);
		return tupleTy(ntypes);
	}
	override bool unifyImpl(Expression rhs,ref Expression[string] subst){
		auto tt=cast(TupleTy)rhs;
		if(!tt||types.length!=tt.types.length) return false;
		return all!(i=>types[i].unify(tt.types[i],subst))(iota(types.length));

	}
	override bool opEquals(Object o){
		if(auto r=cast(TupleTy)o)
			return types==r.types;
		return false;
	}
}

TupleTy unit(){ return tupleTy([]); }

TupleTy tupleTy(Expression[] types)in{
	assert(types.all!(x=>x.type==typeTy));
}body{
	return memoize!((Expression[] types)=>new TupleTy(types))(types);
}

class ArrayTy: Type{
	Expression next;
	private this(Expression next)in{
		assert(next.type==typeTy);
	}body{
		this.next=next;
	}
	override string toString(){
		bool p=cast(FunTy)next||cast(TupleTy)next&&next!is unit;
		return p?"("~next.toString()~")[]":next.toString()~"[]";
	}
	override int freeVarsImpl(scope int delegate(string) dg){
		return next.freeVarsImpl(dg);
	}
	override ArrayTy substituteImpl(Expression[string] subst){
		return arrayTy(next.substitute(subst));
	}
	override bool unifyImpl(Expression rhs,ref Expression[string] subst){
		auto at=cast(ArrayTy)rhs;
		return at && next.unifyImpl(at.next,subst);
	}
	override ArrayTy eval(){
		return arrayTy(next.eval());
	}
	override bool opEquals(Object o){
		if(auto r=cast(ArrayTy)o)
			return next==r.next;
		return false;
	}
}

ArrayTy arrayTy(Expression next)in{
	assert(next&&next.type==typeTy);
}body{
	return memoize!((Expression next)=>new ArrayTy(next))(next);
}

class StringTy: Type{
	private this(){}
	override string toString(){
		return "string";
	}
	override bool opEquals(Object o){
		return !!cast(StringTy)o;
	}
	mixin VariableFree;
}

StringTy stringTy(){ return memoize!(()=>new StringTy()); }

class ForallTy: Type{
	string[] names;
	TupleTy dom;
	Expression cod;
	bool isSquare;
	private this(string[] names,TupleTy dom,Expression cod,bool isSquare)in{
		// TODO: assert that all names are distinct
		assert(names.length==dom.types.length);
		assert(cod.type==typeTy,text(cod));
	}body{
		this.names=names; this.dom=dom; this.cod=cod; this.isSquare=isSquare;
	}
	override string toString(){
		auto c=cod.toString();
		if(cast(TupleTy)cod) c="("~c~")";
		auto del=isSquare?"[]":"()";
		if(!cod.hasAnyFreeVar(names)){
			auto d=dom.types.length==1?dom.types[0].toString():dom.toString();
			if(isSquare||dom.types.length>1||dom.types.length==1&&cast(FunTy)dom.types[0]) d=del[0]~d~del[1];
			return d~" → "~c;
		}else{
			assert(names.length);
			return "∏"~del[0]~zip(names,dom.types).map!(x=>x[0]~":"~x[1].toString()).join(",")~del[1]~". "~c;
		}
	}
	@property size_t nargs(){
		if(auto tplargs=cast(TupleTy)dom) return tplargs.types.length;
		return 1;
	}
	Expression argTy(size_t i)in{assert(i<nargs);}body{
		return dom.types[i];
	}
	override int freeVarsImpl(scope int delegate(string) dg){
		if(auto r=dom.freeVarsImpl(dg)) return r;
		return cod.freeVarsImpl(v=>names.canFind(v)?0:dg(v));
	}
	private ForallTy relabel(string oname,string nname)in{
		assert(names.canFind(oname));
		assert(!hasFreeVar(nname));
		assert(!names.canFind(nname));
	}out(r){
		assert(r.names.canFind(nname));
		assert(!r.names.canFind(oname));
	}body{
		if(oname==nname) return this;
		import std.algorithm;
		auto i=names.countUntil(oname);
		assert(i!=-1);
		auto nnames=names.dup;
		nnames[i]=nname;
		auto nvar=varTy(nname,dom.types[i]);
		return forallTy(nnames,dom,cod.substitute(oname,nvar),isSquare);
	}
	private ForallTy relabelAway(string oname)in{
		assert(names.canFind(oname));
	}out(r){
		assert(!r.names.canFind(oname));
	}body{
		auto nname=oname;
		while(names.canFind(nname)||hasFreeVar(nname)) nname~="'";
		return relabel(oname,nname);
	}
	private string[] freshNames(Expression block){
		auto nnames=names.dup;
		foreach(i,ref nn;nnames)
			if(hasFreeVar(nn)||block.hasFreeVar(nn)||nnames[0..i].canFind(nn)) nn~="'";
		return nnames;
	}
	private ForallTy relabelAll(string[] nnames)out(r){
		assert(nnames.length==names.length);
		foreach(n;nnames) assert(!hasFreeVar(n));
	}body{
		Expression[string] subst;
		foreach(i;0..names.length) subst[names[i]]=varTy(nnames[i],dom.types[i]);
		return forallTy(nnames,dom,cod.substitute(subst),isSquare);
	}
	override ForallTy substituteImpl(Expression[string] subst){
		foreach(n;names){
			bool ok=true;
			foreach(k,v;subst) if(v.hasFreeVar(n)) ok=false;
			if(ok) continue;
			auto r=cast(ForallTy)relabelAway(n).substitute(subst);
			assert(!!r);
			return r;
		}
		auto ndom=cast(TupleTy)dom.substitute(subst);
		assert(!!ndom);
		auto nsubst=subst.dup;
		foreach(n;names) nsubst.remove(n);
		auto ncod=cod.substitute(nsubst);
		return forallTy(names,ndom,ncod,isSquare);
	}
	override bool unifyImpl(Expression rhs,ref Expression[string] subst){
		auto r=cast(ForallTy)rhs; // TODO: get rid of duplication (same code in opEquals)
		if(!r) return false;
		if(isSquare!=r.isSquare||dom.types.length!=r.dom.types.length) return false;
		r=r.relabelAll(freshNames(r));
		Expression[string] nsubst;
		foreach(k,v;subst) if(!names.canFind(k)) nsubst[k]=v;
		auto res=dom.unify(r.dom,nsubst)&&cod.unify(r.cod,nsubst);
		foreach(k,v;nsubst) subst[k]=v;
		return res;
	}
	Expression tryMatch(Expression[] args,out Expression[] gargs)in{assert(isSquare&&cast(ForallTy)cod);}body{
		auto cod=cast(ForallTy)this.cod;
		assert(!!cod);
		if(args.length!=cod.dom.types.length) return null;
		Expression[string] subst;
		foreach(n;names) subst[n]=null;
		foreach(i,a;args){
			if(!cod.dom.types[i].unify(a.type,subst))
				return null;
		}
		gargs=new Expression[](names.length);
		foreach(i,n;names){
			if(!subst[n]) return null;
			gargs[i]=subst[n];
		}
		cod=cast(ForallTy)cod.substitute(subst);
		assert(!!cod);
		return cod.tryApply(args,false);
	}
	Expression tryApply(Expression[] rhs,bool isSquare){
		if(isSquare != this.isSquare) return null;
		if(rhs.length!=names.length) return null;
		foreach(i,r;rhs){
			if(!compatible(dom.types[i],rhs[i].type))
				return null;
		}
		Expression[string] subst;
		foreach(i,n;names)
			subst[n]=rhs[i];
		return cod.substitute(subst);
	}
	override bool opEquals(Object o){
		auto r=cast(ForallTy)o;
		if(!r) return false;
		if(isSquare!=r.isSquare||dom.types.length!=r.dom.types.length) return false;
		r=r.relabelAll(freshNames(r));
		return dom==r.dom&&cod==r.cod;
	}
}

ForallTy forallTy(string[] names,TupleTy dom,Expression cod,bool isSquare=false)in{
	assert(dom&&cod&&names.length==dom.types.length);
}body{
	return memoize!((string[] names,TupleTy dom,Expression cod,bool isSquare)=>new ForallTy(names,dom,cod,isSquare))(names,dom,cod,isSquare);
}

alias FunTy=ForallTy;
FunTy funTy(TupleTy dom,Expression cod,bool isSquare=false)in{
	assert(dom&&cod);
}body{
	return forallTy(dom.types.map!(_=>"").array,dom,cod,isSquare);
}

Identifier varTy(string name,Expression type){
	return memoize!((string name,Expression type){
		auto r=new Identifier(name);
		r.type=type;
		r.sstate=SemState.completed;
		return r;
	})(name,type);
}

class TypeTy: Type{
	this(){ this.type=this; super(); }
	override string toString(){
		return "*";
	}
	override bool opEquals(Object o){
		return !!cast(TypeTy)o;
	}
	mixin VariableFree;
}
private TypeTy theTypeTy;
TypeTy typeTy(){ return theTypeTy?theTypeTy:(theTypeTy=new TypeTy()); }
