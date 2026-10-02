package main

import "../../Engine/Procedural"
import "../../Game/Catalogue"
import "core:fmt"

main :: proc() {
	for kind in Catalogue.Object_Kind {
		fmt.printfln("building %v", kind)
		assembly := Catalogue.Catalogue_Build(kind)
		Procedural.Assembly_Destroy(&assembly)
	}
}
