package require Tcl 9.0
# modeled somewhat afer itcl ensemble
# build a nested dict structure
# later pass to namespace ensemble
#
# part - like itcl part except specify the ensemble name
# as well.  can also specify the namespace to be used,
# defaults to the current one
#
# use delegate to use a command with the same name
# use map to directly add to the map (see namespace ensemble -map)
#
namespace eval ::ensemble {
namespace export ensemble
#
# run a part directly from the dict
#
proc ensemble {cmd args} {
	variable ensemble

	::apply [dict get $ensemble ensemble apply $cmd] {*}$args
}

#
# part - add a subcommand
#
# since the part routine doesn't already exist, place it directly in the dict
#
dict set ensemble ensemble apply part [list {name cmd args body} {
	variable ensemble

	dict set ensemble $name apply $cmd [list $args $body [uplevel namespace current]]
} [namespace current]]

#
# now we can run the part routine using the ensemble proc
#
# create a private routine - can be used as a subcommand but
# isn't listed when an unknown subcommand is shown
# this is slower because of the overhead of the unknown handler
#
ensemble part ensemble private {name cmd args body } {
	variable ensemble

	dict set ensemble $name private $cmd \
		[list ::apply [list $args $body [uplevel namespace current]]]
}

# 
# add a delegated subcommand
#
ensemble part ensemble delegate {name args} {
	variable ensemble

	if {[info exists ensemble]} {
		set delegate [dict getdef $ensemble $name delegate {}]
	}

	lappend delegate {*}$args
	dict set ensemble $name delegate $delegate
}

#
# add a lambda from a proc to the ensemble
#
ensemble part ensemble proc {name args} {
	variable ensemble

	foreach proc $args {
		set qp [uplevel [list namespace which -command $proc]]
		if {$qp eq {}} {return -code error "$proc: not found"}

		set ns [namespace qualifiers $qp]
		set cmd [namespace tail $proc]

		set body [info body $qp]
		set args [lmap arg [info args $qp] {
			if {[info default $qp $arg default]} {
				list $arg $default
				} {
				set arg
			}
		}]

		set lambda [list $args $body $ns]
		dict set ensemble $name apply $cmd $lambda
	}
}

#
# add an arbitrary mapping of a subcommand to one or more words
# (see `namespace ensemble configure xxxx -map` option)
#
ensemble part ensemble map {name cmd args} {
	variable ensemble

	dict set ensemble $name map $cmd $args
}

#
# create a lambda from subcommand map
#
ensemble part ensemble lambda {cmd sub} {
	set qp [uplevel [list namespace which -command $cmd]]

	if {[namespace ensemble exists $qp]} {
		set map [namespace ensemble configure $qp -map]
		if {[dict exists $map $sub]} {
			set map [dict get $map $sub]

			if {[llength $map] == 2} {
				lassign $map cmd lambda
				if {$cmd eq "::apply" && [llength $lambda] == 3}  {
					return $lambda
				}
			}
			return -code error "$qp $sub: not a lambda map"
		}
		return -code error "$qp $sub: subcommand not found"
	}
	return -code error "$cmd: not an ensemble"
}

#
# inject ensemble into the specified scope
# this does not move any dependencies, just the configuration
#
ensemble part ensemble inject {ensemble {scope concat}} {
	set config [uplevel namespace ensemble configure $ensemble]
	set ns [dict get $config -namespace]
	dict unset config -namespace
	dict set config -command $ensemble
	{*}$scope [list namespace eval $ns [list namespace ensemble create {*}$config]]
}

#
# create all ensemble commands as specified and reset
# 
ensemble part ensemble build {{ns {}}}  {
	variable ensemble

	if {$ns eq {}} {
		set ns [uplevel namespace current]
	}
	set ns [::namespace eval $ns {::namespace code {::namespace ensemble create}}]

	dict for {name command} $ensemble {
		set map [dict getdef $command map {}]
		dict for {cmd lambda} [dict getdef $command apply {}] {
			dict set map $cmd [list ::apply $lambda]
		}

		set private [dict getdef $command private {}]

		set cmd [dict getdef $command delegate {}]

		if {[llength $cmd] > 0 || [dict size $private] > 0} {
			lappend cmd {*}[dict keys $map]
		}

		set unknown [if {[dict size $private] > 0} {
			set map [dict merge $map $private]
			list ::apply [list {cmd sub args} {
				dict getdef [namespace ensemble configure $cmd -map] $sub {}
			} [namespace current]]
		}]

		eval $ns [list -command $name -map $map -subcommands $cmd -unknown $unknown]
	}
	unset ensemble
}

#
# build the ensemble
#
ensemble build
}

package provide ensemble-builder 1.0
