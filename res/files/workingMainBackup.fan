// Fantom 
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

    // load instance model into memory and map by id
    recs := ZincReader(input.in).readGrid
    equips:= recs.findAll |row| {row.has("equip")}
    points:= recs.findAll |row| {row.has("point")}
    
    // return a list of equips that do not have an entityType fit
    noEntity:= equipsNoEntityType(equips, ns)
    noEntityEquips:= equipsNoEntityType(equips, ns).colToList("equipName")
    echo("==============================================")
    echo("Equips without entityType fit: $noEntityEquips")
    echo("==============================================")

    // for each equip, provide a report of:
    //   1. points that did not match to a proto
    //   2. protos that matched to mutliple points
    equips.each |equip| {
      equipName:= equip->navName
      echo("Equip being evaluated: $equipName")

      thisEquipPoints:= equipPoints(equip, points)
      grid:= equipProtoMatches(equip, thisEquipPoints, ns)
      //grid.each |row| {echo(row)}
      notMatched:= noProtoMatches(grid)   
      if(notMatched.size == 0) {
        echo(" ")  
      } else {
        echo("The following points did not match to a prototype for this equip:")
        notMatched.each |row| {
            thisNavName:= row->navName
            echo(" - $equipName $thisNavName")
        }
      }
      
      
      dupProtos:= duplicateProtoMatches(grid)
      if(dupProtos == null || dupProtos.size == 0) {
        echo(" ")  
      } else {
        echo("The following prototypes matched to multiple points: \n")
        if(dupProtos != null) {
          uniqueDupProtos:= dupProtos.unique(["protoMatch"])
          uniqueDupProtos.each |row| {
            thisProtoMatch:= row->protoMatch
            echo(" - $thisProtoMatch")
          }
        }
      }
      echo("---------------------------------")
    
    }
    
    return 0
  }

  // get point list for a given equip
  static Grid? equipPoints(Dict equip, Grid points) {
    thisEquipPoints:= points.findAll |row| {row.get("equipRef") == equip.get("id")}
    return thisEquipPoints
  }
  
  // transform a proto record to a list of only applicable tags
  static Str[] reduceProtoToTagList(Dict proto) {

    acc:= Str[,]
    proto.each |val,key| {
      //echo("val: $val, key: $key")
      if(val != null)
        acc= acc.add(key)
    }
    
    //acc= acc.findAll |v| {v != "siteRef" && v != "equipRef" && v != "point"}
    //echo("acc: $acc")

    return acc

  }
  
  //make a grid that maps points to matched protos
  static Grid? equipProtoMatches(Dict equip, Grid points, Namespace ns) {
    
    gb:= GridBuilder()
    gb= gb.addCol("id")
    gb= gb.addCol("navName")
    gb= gb.addCol("equipRef")
    gb= gb.addCol("protoMatch")

    equipId:= equip.get("id")
    
    //Grid equipProtoGrid:= equipProtoTree(equip, ns)
    
    points.each |row| {
      //thisMatch:= equipPointProtoMatch(equip, row, ns)
      thisMatch:= equipPointProtoMatch2(equip, row, ns)
      
      if(thisMatch != null) {
        tagList:= reduceProtoToTagList(thisMatch)
        gb= gb.addRow([row["id"], row["navName"], equipId, tagList])
      } else
        gb= gb.addRow([row["id"], row["navName"], equipId, "no match found"])
    }

    pointGrid:= gb.toGrid

    return pointGrid
  }

  //make a grid that maps points to matched protos 2022-02-18
  static Grid? equipProtoMatches2(Dict equip, Grid points, Namespace ns) {
    
    gb:= GridBuilder()
    gb= gb.addCol("id")
    gb= gb.addCol("navName")
    gb= gb.addCol("equipRef")
    gb= gb.addCol("protoMatch")
    gb= gb.addCol("partialMatches")

    equipId:= equip.get("id")
    
    points.each |row| {
      theseMatches:= equipPointProtoMatch3(equip, row, ns)
      fullMatch:= theseMatches.find |row| {row->isFullMatch}
      closeMatches:= theseMatches.findAll |row| {not row->isFullMatch}

      if(fullMatch != null) {
          thisTagList:= reduceProtoToTagList(fullMatch)
          gb= gb.addRow([row["id"], row["navName"], equipId, thisTagList, null])
      } else if(closeMatches.size > 0) {
        thesePartialMatches:= List[,]
        closeMatches.each |closeMatch| {
          thisTagList:= reduceProtoToTagList(closeMatch)
          thesePartialMatches=  thesePartialMatches.add(thisTagList)
        }
          
        gb= gb.addRow([row["id"], row["navName"], equipId, null, thesePartialMatches]) 
        
      } else {
        gb= gb.addRow([row["id"], row["navName"], equipId, null, null])
      }
    }

    pointGrid:= gb.toGrid

    return pointGrid
  }

  //make a grid of all points within an equip that do not have a protoMatch
  static Grid? noProtoMatches(Grid pointsAndProtos) {
    noMatches:= pointsAndProtos.findAll |row| {row["protoMatch"] == "no match found"}
    noMatches= noMatches.findAll |row| {row.has("navName")}
    return noMatches
  }

  // I think we won't need this with the new matching algo 2022-02-18
  //make grid of points that have no fullMatch or partialMatches 2022-02-18
  static Grid? noProtoMatches2(Grid pointsAndProtos) {
    noMatches:= pointsAndProtos.findAll |row| {not (row.has("protoMatch") or row.has("partialMatches"))}
    noMatches= noMatches.findAll |row| {row.has("navName")}
    return noMatches
  }



   //make a grid of all points within an equip that match to the same proto
  static Grid? duplicateProtoMatches(Grid pointsAndProtos) {
    pointsAndProtos= pointsAndProtos.findAll |row| {row->protoMatch != "no match found"}
    protoMatchList:= pointsAndProtos.unique(["protoMatch"]).colToList("protoMatch")
    //echo("protoMatchList: $protoMatchList")

    //pointsAndProtos.each |row| {echo("pointsAndProtos: $row")}
    acc:= [,]
    
    
    if(protoMatchList.size > 0) {
      protoMatchList.each |protoListItr| {
        protoRows:= pointsAndProtos.findAll |point| {point["protoMatch"] == protoListItr}
        //protoRows.each |row| {echo("protoRow: $row")}
        if(protoRows.size > 1)
          protoRows.each |thisProtoRow| {
            acc= acc.add(thisProtoRow)
        }
      }

      pointsMultiProtos:= Etc.makeDictsGrid(null, acc)
    
      return pointsMultiProtos
    } else {return null}
  }
  
  /* DEPRECATED ---------------------------
  //get matching proto for a given entityType and point {
  static Dict? equipPointProtoMatch(Dict equip, Dict point, Namespace ns){
    Grid entityProtoTree:= equipProtoTree(equip, ns)
    matchedProto:= null
    entityProtoTree.each |row| {
      thisProtoMatches:= equipPointMatchesProto(point, row, ns)
      if(thisProtoMatches) {
        matchedProto= row
      }
    }
  
    return matchedProto
  }
  DEPRECATED --------------------------- */ 

//get matching proto for a given entityType and point {
  static Dict? equipPointProtoMatch2(Dict equip, Dict point, Namespace ns){
    Grid entityProtoTree:= buildProtoTree(equip, ns)
    matchedProto:= null
    entityProtoTree.each |row| {
      thisProtoMatches:= equipPointMatchesProto(point, row, ns)
      if(thisProtoMatches) {
        matchedProto= row
      }
    }
  
    return matchedProto
  }

  //get matching proto and close matches for a given point 2022-02-18
  static Dict[] equipPointProtoMatch3(Dict equip, Dict point, Namespace ns){
    Grid entityProtoTree:= buildProtoTree(equip, ns)
    //matchedProto:= null
    matchedProtos:= Dict[,]
    entityProtoTree.each |row| {
      thisProtoMatches:= equipPointMatchesProto(point, row, ns)
      if(thisProtoMatches) {
        row= Etc.dictSet(row, "isFullMatch", true)
        matchedProtos= matchedProtos.addRow(row)
      } else {
        protoIsCloseMatch:= protoMatchesEquipPoint(point, row, ns)
        if(protoIsCloseMatch) {
          row= Etc.dictSet(row, "isFullMatch", false)
          matchedProtos= matchedProtos.addRow(row)
        }
      }
    }
  
    return matchedProtos
  }
  
  /*
  //function that returns any match between point and proto in a dict
  static Dict defMatches(Dict point, Dict proto, Namespace ns) {
    protoReflect:= ns.reflect(proto).toGrid
    pointReflect:= ns.reflect(point).toGrid

    gb:= GridBuilder()
    gb= gb.addCol("protoDef")
    gb= gb.addCol("matchInPoint")

    protoReflect.each |protoRow| {
      isMatched:= false
      match:= pointReflect.find |ptRow| {ptRow["def"] == protoRow["def"]}
      if(match is Dict) isMatched= true
      gb= gb.addRow([protoRow["def"], isMatched])
    }

    matchGrid:= gb.toGrid

    if (matchGrid.all |row| {row->matchInPoint == false})
      return makeDict2("isFullMatch", false, "defMatches", [,])
    else if (matchGrid.all |row| {row->matchInPoint == true})
      return makeDict2("isFullMatch",true, "defMatches", matchGrid.colToList("protoDef"))
    else
      return makeDict2("isFullMatch",false, "defMatches", matchGrid.findAll |row| {row->matchInPoint}.colToList("protoDef"))
  }
  */
  
  //return true if the proto matches ALL defs of the point (proto.contains(pointDefs))
  static Bool protoMatchesEquipPoint(Dict point, Dict proto, Namespace ns) {
    protoReflect:= ns.reflect(proto).toGrid
    //protoReflect.each |row| {echo(row)}

    pointReflect:= ns.reflect(point).toGrid
    //pointReflect.each |row| {echo(row)}
    
    
    gb:= GridBuilder()
    gb= gb.addCol("pointDef")
    gb= gb.addCol("matchInProto")

    pointReflect.each |pointRow| {
      isMatched:=false
      match:= protoReflect.find |poRow| {poRow["def"] == pointRow["def"]}
      if(match is Dict) isMatched= true
      gb= gb.addRow([pointRow["def"], isMatched])
    }
    
    matchGrid:= gb.toGrid

    isMatched:= matchGrid.all |row| {row->matchInProto == true}
    //echo("isMatched?: $isMatched")

    return isMatched
  }
  
  //return true if the point matches ALL defs of the proto (point.contains(protoDefs))
  static Bool equipPointMatchesProto(Dict point, Dict proto, Namespace ns) {
    protoReflect:= ns.reflect(proto).toGrid
    //protoReflect.each |row| {echo(row)}

    pointReflect:= ns.reflect(point).toGrid
    //pointReflect.each |row| {echo(row)}
    
    
    gb:= GridBuilder()
    gb= gb.addCol("protoDef")
    gb= gb.addCol("matchInPoint")

    protoReflect.each |protoRow| {
      isMatched:=false
      match:= pointReflect.find |ptRow| {ptRow["def"] == protoRow["def"]}
      if(match is Dict) isMatched= true
      gb= gb.addRow([protoRow["def"], isMatched])
    }
    
    matchGrid:= gb.toGrid

    isMatched:= matchGrid.all |row| {row->matchInPoint == true}
    //echo("isMatched?: $isMatched")

    return isMatched
  }
  
  //return bestFit entities for given equip with an entityType match (not 'equip' only)
  static Grid? equipsHaveEntityType(Grid equips, Namespace ns) {
    gb:= GridBuilder()
    gb.addCol("equipName")
    gb.addCol("bestFit")

    equipEntityGrid:= gb

    equips.each |equip, i| {
      equipName:= equips[i].get("navName")
      equipDefs:= ns.reflect(equip)
      equipBestFit:= equipDefs.entityTypes()

      equipEntityGrid= equipEntityGrid.addRow([equipName, equipBestFit])
    }

    haveEntity:= equipEntityGrid.toGrid().findAll |row| {row->bestFit.toStr != "[equip]"}

    return haveEntity
  }

  // return equips that only match to 'equip' entityType
  static Grid? equipsNoEntityType(Grid equips, Namespace ns) {
    gb:= GridBuilder()
    gb.addCol("equipName")
    gb.addCol("bestFit")

    equipEntityGrid:= gb

    equips.each |equip, i| {
      equipName:= equips[i].get("navName")
      equipDefs:= ns.reflect(equip)
      equipBestFit:= equipDefs.entityTypes()

      equipEntityGrid= equipEntityGrid.addRow([equipName, equipBestFit])
    }
    
    noEntity:= equipEntityGrid.toGrid().findAll |row| {row->bestFit.toStr == "[equip]"}

    return noEntity
  }

  static Grid? equipProtoTree(Dict equip, Namespace ns) {
    equipName:= equip.get("navName")

    firstLevelProtos:= ns.protos(equip).findAll |row| {Etc.toGrid(row).colNames.size > 3}

    acc:= firstLevelProtos

    firstLevelProtos.each |proto1| {

      secondLevelProtos:= ns.protos(proto1).findAll |row| {Etc.toGrid(row).colNames.size > 3}
      if(secondLevelProtos.size > 0) {
        secondLevelProtos.each |proto2| {
          acc= acc.add(proto2)
          
          thirdLevelProtos:= ns.protos(proto2).findAll |row| {Etc.toGrid(row).colNames.size > 3}
          if(thirdLevelProtos.size > 0) {
            thirdLevelProtos.each |proto3| {
              acc= acc.add(proto3)
            
              fourthLevelProtos:= ns.protos(proto3).findAll |row| {Etc.toGrid(row).colNames.size > 3}
              if(fourthLevelProtos.size > 0) {
                fourthLevelProtos.each |proto4| {
                  acc= acc.add(proto4)

                }
              }
            }
            
          }
        }
        
      }
      
    }
  
    grid:= Etc.makeDictsGrid(null, acc)
    grid= grid.findAll |row| {row.has("sensor") || row.has("sp") || row.has("cmd")}
    /*
    grid.each |row| {
      echo("tacos row: $row")
    }

    */
    
    return grid
  }

  static Grid? buildProtoTree(Dict equip, Namespace ns) {
    equipName:= equip.get("navName")
    
    acc:= Dict[,]
    equipProtoTree2(acc, equip, ns)
    grid:= Etc.makeDictsGrid(null, acc)
    
    return grid

  }

  static Void equipProtoTree2(Dict[] tree, Dict equip, Namespace ns) {
    //get the equip's protos and split them into points and equips
    theseProtos:= ns.protos(equip).findAll |row| {Etc.toGrid(row).colNames.size > 3}
    equipProtos:= theseProtos.findAll |p| {p.has("equip")}
    pointProtos:= theseProtos.findAll |p| {p.has("point")}.findAll |row| {row.has("sensor") || row.has("sp") || row.has("cmd")}
    
    //for points, add to tree trid
    tree= tree.addAll(pointProtos)
    
    //for the equips, cycle through each and run equipProtoTree
    if(equipProtos.size > 0) {
      equipProtos.each |equipProto| {
        equipProtoTree2(tree, equipProto, ns)
      }
    }
  }

}
