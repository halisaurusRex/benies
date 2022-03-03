// Copyright (c) 2022, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   22 Feb 22  Hali Sanderlin  Creation
//    1 Mar 22  Hali Sanderlin  Updated structure (BF)

using util
using haystack
using defc
using def

class Main : AbstractMain
{
  @Arg { help = "Zinc input file with data model to validate" }
  File? input

  ** Top level main
  override Int run()
  {
    load
    validateEquips
    return 0
  }

  ** Initialize our data structures from the command line arg
  Void load()
  {
    // init namespace
    this.ns = DefCompiler().compileNamespace

    // parse zinc data into memory and sort by dis
    this.recs = ZincReader(input.in).readGrid.toRows

    // map recs by id
    this.byId = Ref:Dict[:].setList(recs) { it.id }

    // now sort recs by dis
    this.recs = recs.dup.sort |a, b| { toDis(a) <=> toDis(b) }

  }

  ** Run validation on all equip recs
  Void validateEquips()
  {
    recs.each |rec| { if (rec.has("equip")) validateEquip(rec) }
  }

  ** Validate a single equip record
  Void validateEquip(Dict equip)
  {
    echo
    echo("-- " + toDis(equip) + " --")

    // reflect the equip subtypes
    types := ns.reflect(equip).entityTypes
    if (types.size == 1 && types[0].name == "equip")
    {
      echo("   WARN: equip does not define any subtype tags")
      return
    }

    // process points under this equip
    validatePoints(equip)
  }

  ** Validate the points under the given equip
  Void validatePoints(Dict equip)
  {
    // find all the prototype children for entity types
    protos := findProtoPoints(Dict[,], equip)
     
    // find children points
    points := recs.findAll |rec| { rec.has("point") && rec["equipRef"] == equip.id }
    // report on each point
    points.each |point| { validatePoint(equip, protos, point) } 
  }
  
  ** Validate a single point under the given equip 
  Void validatePoint(Dict equip, Dict[] protos, Dict point)
  {
    
    // get list of tags on point to match to protos
    thisPointTagList:= reduceProtoToTagList(point) //replace with Etc.dictFindAll

    // set hasFullMatch flag to false
    hasFullMatch:= false

    // get the list of matches for this point
    theseMatches:= getPartialMatches(equip, protos, point)
    
    // if theseMatches returns a list of Str, it has a single, complete match
    if(theseMatches is Str[])
      hasFullMatch= true
    
    // return output to console that aligns with point's match condition
    if (hasFullMatch) 
    {
      a:=1 //echo("   " + toDis(point) + " | proto:" + theseMatches)
    } 
    else if (theseMatches.isEmpty)
    {
      echo("   " + toDis(point) + "->" + reduceProtoToTagList(point)  + ": NO MATCH")
    }
    else
    {
      echo("   " + toDis(point) + "->" + reduceProtoToTagList(point) + ": AMBIGUOUS MATCH")
      theseMatches.each |matchList| {
        echo("     - $matchList")
      }
    }
  }

  ** Create a list of matches. If 100% match, update point and return null, else return list of top matches
  List? getPartialMatches (Dict equip, Dict[] protos, Dict point)
  {
    // create empty list to store prototype matches
    matchedProtos:= Dict[,]
    
    // if the protos variable is empty, return an empty list.
    if (protos.isEmpty) return [,]
      
    // iterate the protos and if a match is found, add to matchedProtos list
    protos.each |row| 
    {
      thisPercentMatch:= protoMatchPercent(point, row, ns)
      tags:= reduceProtoToTagList(row)
      Dict newRow:= Etc.makeDict2("tagList", tags, "percentMatch", thisPercentMatch)
      matchedProtos= matchedProtos.add(newRow)
    }
    
    // reverse sort matchedProtos list
    closeMatches:= Etc.makeDictsGrid(null, matchedProtos).sortColr("percentMatch")
    
    // get the highest percent match
    bestMatchPercent:= closeMatches[0]->percentMatch
    
    // if there is a full match (100%), return the list of tags of the matched prototype (returns Str[])
    if (bestMatchPercent == Number(100)) 
    {
      thisTagList:= closeMatches[0]->tagList
      point= Etc.dictSet(point, "protoMatch", thisTagList)
      return thisTagList
    }
    // if not, return a list of the matched prototypes tags (returns List[])
    else
    {
      // filter matches for only those with the highest match precent
      bestMatches:= closeMatches.findAll |matchRow| {matchRow->percentMatch == bestMatchPercent}
      thesePartialMatches:= List[,]
      
      // add the bestMatches to thisPartialMatches var
      bestMatchSize:= bestMatches.size
      if (bestMatchSize >= 5)
        bestMatches= bestMatches[0..4]
      
      bestMatches.each |bestMatch| 
      {
        thisTagList:= bestMatch->tagList 
        thesePartialMatches=  thesePartialMatches.add(thisTagList)
      }
      
      return thesePartialMatches
    }
    
  }

  ** return percentage of matching defs between point and proto (0-100)
  Number protoMatchPercent(Dict point, Dict proto, Namespace ns) 
  {
    // reflect prototype to get tags to match
    protoReflect:= ns.reflect(proto).toGrid.findAll |row| {(!(row->def.toStr.contains("Ref") || row->def.toStr == "point"))}.keepCols(["def"])
    
    // reflect point to get tags to match
    pointReflect:= ns.reflect(point).toGrid.findAll |row| {(!(row->def.toStr.contains("Ref") || row->def.toStr == "point"))}.keepCols(["def"])

    matchGrid:= pointReflect.findAll |protoDef| {protoReflect.colToList("def").contains(protoDef->def)}

    matchedSize:= Number(matchGrid.size)
    gridSize:= Number(protoReflect.size)
    
    // calculate matchedPercent
    isMatched:= ((matchedSize / gridSize) * Number(100))
    
    return isMatched
  }

  ** transform a proto record to a list of only applicable tags
  Str[] reduceProtoToTagList(Dict proto) 
  {
    acc:= Str[,]
    proto.each |val,key| 
    {
      if (val != null) 
      {
        if (!(key.contains("Ref") || key == "point" || key == "isFullMatch"))
          acc= acc.add(key)
      }
    }  

    return acc
  }

  ** Compute the list of point prototype children
  Dict[] findProtoPoints(Dict[] acc, Dict equip)
  {
    ns.protos(equip).each |proto|
    {
       // strip out ref tags
       proto = Etc.dictFindAll(proto) |v| { v isnot Ref }
       
       // skip the empty point/equip protos
       size := Etc.dictNames(proto).size 
       if (size == 1) return 
        
       // if its a point accumulate it; if equip then recurse it
       if (proto.has("point"))
         acc.add(proto)
       else if (proto.has("equip"))
         findProtoPoints(acc, proto)
    }
    acc= acc.findAll |p| {p.has("point")}.findAll |row| {row.has("sensor") || row.has("sp") || row.has("cmd")}
    return acc
  }

  ** Evaluate the 'disMacro' tag and return full display name for given rec
  Str toDis(Dict r)
  {
    pattern := r["disMacro"]
    if (pattern == null) return r.dis

    m := haystack::Macro(pattern, Etc.emptyDict)
    vars := Str:Obj[:].setList(m.vars)
    vars = vars.map |name->Str|
    {
      tag := r[name]
      if (tag == null) return name
      if (tag is Ref)
      {
        // does not handle circular recursion properly
        referent := byId[tag]
        if (referent != null) return toDis(referent)
      }
      return tag.toStr
    }
    return haystack::Macro(pattern, Etc.makeDict(vars)).apply
  }
  
  Namespace? ns       // initialized in load() method
  Dict[]? recs        // initialized in load() method
  [Ref:Dict]? byId    // initialized in load() method
}