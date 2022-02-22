// Copyright (c) 2022, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   22 Feb 22  Hali Sanderlin  Creation
//

using util
using haystack
using defc
using def

class Main : AbstractMain
{
  @Arg { help = "Zinc input file with data model to validate" }
  File? input

  override Int run()
  {
    // load namespace into memory
    ns := defc::DefCompiler().compileNamespace
    echo("Read namespace $ns.libsList")

    //
    // load instance model into memory and map by id
    //
    recs := ZincReader(input.in).readGrid
    equips:= recs.findAll |row| {row.has("equip")}
    points:= recs.findAll |row| {row.has("point")}
    
    //
    // return a list of equips that do not have an entityType fit
    //
    noEntity:= equipsNoEntityType(equips, ns)
    noEntityEquips:= equipsNoEntityType(equips, ns).colToList("equipName")
    echo("==============================================")
    echo("Equips without entityType fit: $noEntityEquips")
    echo("==============================================")

    //
    // for each equip, provide a report of:
    //   1. points with matches
    //      - if there is a fullMatch, report fullMatch OR
    //      - if there is partialMatches, report number of partialMatches
    //        - if parameter showPartialMatches is TRUE, list partialMatches
    //      - if no match, report "no matches"
    //   2. protos that matched to mutliple points
    //
    equips.each |equip| {
      equipName:= equip->navName
      echo("Equip being evaluated: $equipName\n")

      thisEquipPoints:= equipPoints(equip, points)
      grid:= equipProtoMatches(equip, thisEquipPoints, ns)
 
      notMatched:= noProtoMatches(grid)   

      
      dupProtos:= duplicateProtoMatches(grid)
      if (dupProtos == null || dupProtos.size == 0) 
      {
        echo(" ")  
      } 
      else 
      {
        echo("Prototypes that mapped to >1 point:")
        if (dupProtos != null) 
        {  
          uniqueDupProtos:= dupProtos
          uniqueDupProtos.each |row| 
          {
            thisProtoMatch:= row->protoMatch
            thisPtName:= row->pointName
            echo(" - $thisProtoMatch ===> $thisPtName")
          }
        }
      } 
      echo("---------------------------------")
    
    }

    return 0
  }

  //
  // get point list for a given equip
  //
  static Grid? equipPoints(Dict equip, Grid points) 
  {
    thisEquipPoints:= points.findAll |row| {row.get("equipRef") == equip.get("id")}
    return thisEquipPoints
  }
  
  //
  // transform a proto record to a list of only applicable tags
  //
  static Str[] reduceProtoToTagList(Dict proto) 
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

  //
  // make a grid that maps points to matched protos
  //
  static Grid? equipProtoMatches(Dict equip, Grid points, Namespace ns) 
  {  
    gb:= GridBuilder()
    gb= gb.addCol("id")
    gb= gb.addCol("pointName")
    gb= gb.addCol("equipRef")
    gb= gb.addCol("pointTagList")
    gb= gb.addCol("protoMatch")
    gb= gb.addCol("partialMatches")

    equipId:= equip.get("id")
    points.each |row| 
    {
      pointName:= "no name found"
      if (row.has("navName"))
        pointName= row->navName
      else if (row.has("dis"))
        pointName= row->dis

      thisPointTagList:= reduceProtoToTagList(row)

      theseMatches:= equipPointProtoMatch(equip, row, ns)
      if (theseMatches.size != 0) 
      {
        fullMatch:= theseMatches.find |matchRow| {matchRow->percentMatch == Number(100)}
        closeMatches:= Etc.makeDictsGrid(null, theseMatches).sortColr("percentMatch")
        if (fullMatch != null) 
        {
            thisTagList:= fullMatch->tagList
            gb= gb.addRow([row["id"], pointName, equipId, thisPointTagList, thisTagList, null])
        } 
        else if (closeMatches.size > 0) 
        {
          bestMatchPercent:= closeMatches[0]->percentMatch
          bestMatches:= closeMatches.findAll |matchRow| {matchRow->percentMatch == bestMatchPercent}
          thesePartialMatches:= List[,]
          
          bestMatchSize:= bestMatches.size
          if (bestMatchSize >= 5)
            bestMatches= bestMatches[0..4]
          
          bestMatches.each |bestMatch| 
          {
            thisTagList:= bestMatch->tagList 
            thesePartialMatches=  thesePartialMatches.add(thisTagList)
          }
          
          gb= gb.addRow([row["id"], pointName, equipId, thisPointTagList, null, thesePartialMatches]) 
           
        
        } 
        else 
        {
          gb= gb.addRow([row["id"], pointName, equipId, thisPointTagList, null, null])
        }
      }
    }
    
    pointGrid:= gb.toGrid
    

    return pointGrid
  }

  // 
  // make grid of points that have no fullMatch or partialMatches
  //
  static Grid? noProtoMatches(Grid pointsAndProtos) 
  {
    noMatches:= pointsAndProtos.findAll |row| {row.has("partialMatches")} //! (row.has("protoMatch") || 
    noMatches.each |row| 
    {
      thisName:= row->pointName
      thisTagList:= row->pointTagList
      echo("Best matches for: $thisName $thisTagList")
      List theseMatches:= row->partialMatches
      theseMatches.each |matchList| 
      {
        echo("  - $matchList")
      }
      echo("\n")
    }
    return noMatches
  }
  
  //
  // make a grid of all points within an equip that match to the same proto
  //
  static Grid? duplicateProtoMatches(Grid pointsAndProtos) 
  {
    pointsAndProtos= pointsAndProtos.findAll |row| {row.has("protoMatch")}
    protoMatchList:= pointsAndProtos.unique(["protoMatch"]).colToList("protoMatch")
    
    acc:= [,]
    
    if (protoMatchList.size > 0) 
    {
      protoMatchList.each |protoListItr| 
      {
        protoRows:= pointsAndProtos.findAll |point| {point["protoMatch"] == protoListItr}
        if (protoRows.size > 1) 
        {
          protoRows.each |thisProtoRow| 
          {
            acc= acc.add(thisProtoRow)
          }
        }
      }

      pointsMultiProtos:= Etc.makeDictsGrid(null, acc)
    
      return pointsMultiProtos
    } 
    else {return null}
  }

  //
  // get matching proto and close matches for a given point
  //
  static Dict[] equipPointProtoMatch(Dict equip, Dict point, Namespace ns)
  {
    Grid entityProtoTree:= buildProtoTree(equip, ns)
    matchedProtos:= Dict[,]
    entityProtoTree.each |row| 
    {
      thisPercentMatch:= equipPointMatchesProto(point, row, ns)
      Dict newRow:= Etc.makeDict2("tagList", reduceProtoToTagList(row), "percentMatch", thisPercentMatch)
      matchedProtos= matchedProtos.add(newRow)
    }
    
    return matchedProtos
  }

  //
  // return true if the point matches ALL defs of the proto (point.contains(protoDefs))
  //
  static Number equipPointMatchesProto(Dict point, Dict proto, Namespace ns) 
  {
    protoReflect:= ns.reflect(proto).toGrid.findAll |row| {(!(row->def.toStr.contains("Ref") || row->def.toStr == "point"))}.keepCols(["def"])
    pointReflect:= ns.reflect(point).toGrid.findAll |row| {(!(row->def.toStr.contains("Ref") || row->def.toStr == "point"))}.keepCols(["def"])
    
    gb:= GridBuilder()
    gb= gb.addCol("protoDef")
    gb= gb.addCol("matchInPoint")

    protoReflect.each |protoRow| 
    {
      isMatched:=false
      match:= pointReflect.find |ptRow| {ptRow["def"] == protoRow["def"]}
      if (match is Dict) isMatched= true
      gb= gb.addRow([protoRow["def"], isMatched])
    }
    
    matchGrid:= gb.toGrid
    isMatchedList:= matchGrid.findAll|row| {row->matchInPoint == true}

    matchedSize:= Number(isMatchedList.size)
    gridSize:= Number(matchGrid.size)
    isMatched:= ((matchedSize / gridSize) * Number(100))

    return isMatched
  }
  
  //
  // return bestFit entities for given equip with an entityType match (not 'equip' only)
  //
  static Grid? equipsHaveEntityType(Grid equips, Namespace ns)
  {
    gb:= GridBuilder()
    gb.addCol("equipName")
    gb.addCol("bestFit")

    equipEntityGrid:= gb

    equips.each |equip, i| 
    {
      equipName:= equips[i].get("navName")
      equipDefs:= ns.reflect(equip)
      equipBestFit:= equipDefs.entityTypes()

      equipEntityGrid= equipEntityGrid.addRow([equipName, equipBestFit])
    }

    haveEntity:= equipEntityGrid.toGrid().findAll |row| {row->bestFit.toStr != "[equip]"}

    return haveEntity
  }

  //
  // return equips that only match to 'equip' entityType
  //
  static Grid? equipsNoEntityType(Grid equips, Namespace ns) 
  {
    gb:= GridBuilder()
    gb.addCol("equipName")
    gb.addCol("bestFit")

    equipEntityGrid:= gb

    equips.each |equip, i| 
    {
      equipName:= equips[i].get("navName")
      equipDefs:= ns.reflect(equip)
      equipBestFit:= equipDefs.entityTypes()

      equipEntityGrid= equipEntityGrid.addRow([equipName, equipBestFit])
    }
    
    noEntity:= equipEntityGrid.toGrid.findAll |row| {row->bestFit.toStr == "[equip]"}

    return noEntity
  }

  static Grid? buildProtoTree(Dict equip, Namespace ns) 
  {
    equipName:= equip.get("navName")
    
    acc:= Dict[,]
    equipProtoTree(acc, equip, ns)
    grid:= Etc.makeDictsGrid(null, acc)
    
    return grid
  }

  static Void equipProtoTree(Dict[] tree, Dict equip, Namespace ns) 
  {
    //
    // get the equip's protos and split them into points and equips
    //
    theseProtos:= ns.protos(equip).findAll |row| {Etc.toGrid(row).colNames.size > 3}
    equipProtos:= theseProtos.findAll |p| {p.has("equip")}
    pointProtos:= theseProtos.findAll |p| {p.has("point")}.findAll |row| {row.has("sensor") || row.has("sp") || row.has("cmd")}
    
    //
    // for points, add to tree trid
    //
    tree= tree.addAll(pointProtos)
    
    //
    // for the equips, cycle through each and run equipProtoTree
    //
    if (equipProtos.size > 0) 
    {
      equipProtos.each |equipProto| 
      {
        equipProtoTree(tree, equipProto, ns)
      }
    }
  }
}
