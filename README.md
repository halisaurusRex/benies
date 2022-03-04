# benies
**Steps to perform**

 1. Install the latest Haxall version
    https://haxall.io/doc/docHaxall/Setup
 3. Download benies.pod from the `lib/fan/` folder and drop it in the `lib/fan/` directory of your Haxall installation
 4. From the command line, run with the location of the Zinc file you would like to test as a parameter
 
 *for example (run from the `haxall/bin/` directory):*
 ```
 fan benies c:\fan\files\alpha.zinc
 ```

## Description
Taking in a zinc file of a site with associated equipment and point records, keyed by ID, it is designed to answer the following three questions with regards to matching points with Haystack4 [prototypes](https://project-haystack.org/doc/docHaystack/Protos):
-	What H4 [entityType](https://project-haystack.org/doc/appendix/equip) is my equipment being identified as?
-	Which points are not matched to an existing H4 prototype as tagged?
-	Within a single piece of equipment, are there multiple points that are matching to the same prototype?

**NOTE:** Example Zinc files are available within the `res/files/` directory.
