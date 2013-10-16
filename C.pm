package		C;

require		5.6.0 ;

require		Exporter;

@ISA		= qw(Exporter);

@EXPORT		= qw(DumpDatastructures Load %NameSpaces @Directives);



#-----------------------------------------------------------------------------

#	Subroutines

#-----------------------------------------------------------------------------

sub PreProcess

{

        my($filename) = @_;

	printf STDOUT "Loading $filename\n";

        open IFILE, $filename or die "ERROR: Can't open $filename\n";

        {

                local $/ = undef;       # no line delimiter

                $file = <IFILE>;        # read entire file

                

# COMMENT REMOVAL REGEX

# skip quoted strings|delete C comments|delete C++ comments|change comments to a single space

# ignore white space, treat as single line,evaluate result, repeat globally

                 $file =~  s! ((['"]) (?: \\. | .)*? \2) |/\* .*? \*/ |// [^\n\r]*! $1 || ' '!xseg;

                 

# { REPLACED by {\n

# "{" is treated as a delimiter for some contructs, which means constructs following { on the same

# line will be skipped by PrepareKwdString so we replace every accurence of { by {\n here

# to avoid the above possibility.similarly for } we replace every accurence of } by \n} here

                 $file =~  s!{!{\n!xsg;

                 $file =~  s!}!\n}!xsg;

         }



        # $file now contains the entire preprocessed file

        close IFILE;

        1;

}



sub Load

{

        @Directives = ();	     # reset structures for new file

        %NameSpaces = ();



        my ($filename) = @_;

	local $namespace = "DEFAULT"; # namespace name,default for global classes,enums

	local $lastdelimiter = undef; # last delimiter

        local $keywdstring = undef;   # string containg the fields for the keyword construct

        local @fields = undef;        # array of fields for the keyword construct

        local $scope = 0;             # maintains count of opened scopes i.e no of { found.

        local $state = 0;             # current state, 0 for global/default namespace given by $namespace

	local $name = undef;          # current class, struct or enum name

        local @scopes = undef;        # stack of all opened scopes,where each element is either

                                      # a number, or a 3 tuple <$state:$name:$scopeno>

        local $hash = undef;          # Reference to hash corresponding to $state

        local @Hashes = undef;

        local $access = "DEFAULT";    # specifies access for class,struct members

                                      # changes on finding public:,protected:,private: access

                                      # specifiers, is equal to DEFAULT by default

        local $dummycounter =0;       # counter for handling enums,structs,typedefs without names



   	# States:

   	# 0	Global/Default namespace

	# 1	In Namespace

    	# 2	In Class

	# 3     In Struct

   	# 4	In Enum

   	# 5     In Struct typedefs

   	# 6     In Enum typedefs

	# 7	In Functions





###### REGULAR EXPRESSIONS FOR C SHARP CONSTRUCTS #####

###### PLEASE DO NOT CHANGE THIS REGULAR EXPRESSIONS WITHOUT UNDERSTANDING THE CONTEXT/PURPOSE #######



	# regex for directives

        $rgxincludes = "^\#include";

        

        # regex for namespace

        $rgxnamespace = "^namespace";

        

        # regex for class

        $rgxclass = "^class";

        

       	# regex for structs

        $rgxstruct = "^struct";

        #--

	

	# regex for enums

        $rgxenum = "^enum";



#This is not proper. Need to find a proper expression for enum constant or just use

#preparekwdstring to get the entire enum defn in the enum construct



        # regex for enum constants

	$rgxenumconsts = "^(,)?\\w+\\s*(\\=\\s*[0-9xXa-fA-F]+)?\\s*\\,?";

	#--

	

        # regex for typedef's

        $rgxtpdef = "^typedef";

	#--



      	# regex for access specifiers

	$rgxaccess = "((public|protected|private)\\s*:)";

	#--



        # regex for type

        $rgxtypemodifiers = "(unsigned|signed|const|volatile)";

        #$rgxtype = "((\\w+)(\\s*([&\\*]\\s*)*))";

        $rgxtype = "(([\\w\\:]+)(\\s*([&\\*]\\s*)*))";

        #--

        

        #regex for params

        $rgxparamdef = "(($rgxqualifiers\\s+)*($rgxtype)(\\s+(\\w+))?)";

        $rgxparams = "($rgxparamdef(\\s*,\\s*$rgxparamdef\\s*)*)?";

        #--

        

        # regex for qualifiers

        $rgxqualifiers = "(static|virtual|override|abstract|const)"; # TODO: add other possibilities

        #---

        

	# regex for function pointers, TODO:changing this will affect the handling due to change in backrefs

	$rgxfptr = "(typedef\\s+)?($rgxtype)\\s*\\(\\s*(\\w+\\s*)?\\*\\s*(\\w+)\\s*\\)\\s*\\(\\s*$rgxparams\\s*\\)";

        #--

	

	# regex for data and properties

	$rgxdecl = "^($rgxaccess\\s+)?($rgxqualifiers\\s+)*($rgxtype)\\s+\\w+\\s*";

	$rgxdata = "^(($rgxaccess\\s+)?($rgxqualifiers\\s+)*($rgxtype)\\s+\\w+)(\\s*=(.*))?\\s*;\$";

	#--



        # regex for functions

        # will not work if return type exists on another line and rest exists on other

        #$rgxfunction = "^\\w+\\s*[&\\*]?\\s+\\w+\\s*\\(.*";

#       $rgxfunction = "^(~)?($rgxqualifiers\\s+)*(($rgxtype)\\s+)?\\w+\\s*\\(.*";

        #TODO: handle operator functions in Dofunctions

        $rgxfunction = "^($rgxqualifiers\\s+)*(($rgxtype)\\s+)?(~)?(\\w+|operator\\s*[\\=\\+\\-\\&\\*\\!\\^\\*\\(\\)\\[\\]\\{\\}]+)\\s*\\(.*";

        # TODO: regexs for function decl and defn are not working well currently, so not being used in DoFunctions

	$rgxfunctdecl = "^(~)?($rgxqualifiers\\s+)*(($rgxtype)\\s+)?\\w+\\s*\\(\\s*$rgxparams\\s*\\)(\\s+const)?\\s*;\$" ;

	$rgxfunctdefn = "^(~)?($rgxqualifiers\\s+)*(($rgxtype)\\s+)?\\w+\\s*\\(\\s*$rgxparams\\s*\\)(\\s*:\\s*base\\(.*\\))?\\s*{\$";

	#--

	

        $pattern = "$rgxincludes|$rgxnamespace|$rgxclass|$rgxstruct|$rgxenum|$rgxenumconsts|$rgxtpdef|$rgxfunction|$rgxaccess|{|}|};";

###### REGULAR EXPRESSIONS END #####



	# Preprocess the input file and store the contents in the string $file

        &PreProcess($filename);

	@FileStream  = split(/(\n)/,$file);



        for($index = 0;$index <(scalar @FileStream);$index++)

	{

                $line = $FileStream[$index];

     		$line =~ s/^\s*//g;

     		$line =~ s/\s*$//g;

     		

		# skip lines containg comments. Not needed now.Can be removed after testing thoroughly

     		next if ($line =~ /^\/\// or $line =~ /^\/\*/ or $line =~ /^\*\*/ or $line =~ /^\*/);

     		

		# process only those lines which contain keyword or pattern we are interested in.

     		next unless ($line =~ /$pattern/);

                chomp $line;

                @fields = split /\s+/, $line;

                $keywdstring = $line;

                #

                # These lines handle directive statements

                #

                if($line =~ /$rgxincludes/)

                {

                        &DoDirectives;

                        next;

                }

                #

		# These lines start the definition of new namespace(s)

     		#

     		if($line =~ /$rgxnamespace/ )

     		{

                       &PrepareKwdString("^{|{\$");

                       &DoNameSpace;

                       next;

     		}

     		#

     		# These lines handle the access specifiers

     		# set $access according to the access specifier found

     		#

     		if($line =~ /$rgxaccess/)

		{

        		if($line =~ /^public:/)

                        {

                               $access = "public";

                        }

                        elsif($line =~ /^protected:/)

                        {

                                $access = "protected";

                        }

                        elsif($line =~ /^private:/)

                        {

                                $access = "private";

                        }

		}

     		#

		# These lines start the definition of new class,enum or struct

     		#

     		if($line =~ /$rgxclass/ )

     		{

                        &PrepareKwdString("^{|{\$|;\$");

			if ($lastdelimiter ne ";") # don't handle forward declarations for now

			{

                        	&DoClass;

			}

                        next;

     		}

     		if($line =~ /$rgxenum/)

     		{

                        &PrepareKwdString("^{|{\$|;\$");

                        &DoEnum;

                        next;

     		}

     		if($line =~ /$rgxstruct/)

     		{

                        &PrepareKwdString("^{|{\$|;\$");

                        if ($lastdelimiter ne ";") # don't handle forward declarations for now

			{

                                &DoStruct;

                        }

                        next;

     		}



                #

		# These lines start the definition of class,enum or struct members

     		#



		

                #

		# These lines handle special symbols

     		# PS: The order of handling { , members & } is as below and should not be changed

     		# until you are able to remove the if(mempubli.. ) check

     		# see TODO for members below

     		#

		if($line =~ /}|};/)

     		{

                        if($line =~ /};/)

                        {

                               # End of class/struct reset $access to default

                               $access = "DEFAULT"

                        }

                        if($line =~ /}\s*(\w+(\s*,\s*[* \w]+)*)\s*;/) #TODO: Need a better way

                        {

                                my $tname = $1;

                                # reset the typedef name to this

                                # or add a data entry

                                # based on whether the state corresponds to

                                # typedef or simply a nested struct

                                

                                if($state == 5 or $state == 6)

                                {

                                        if( ref($hash) ne "HASH" )

                                        {

                                                die "ERROR: Did not find parent hash reference in \$hash \n";

                                        }

                                        my $typedef = $hash;

                                        $typedef->{TYPENAME} = $tname;

                                }

                                else

                                {

                                        #TODO: add data definition in the parent of the current construct with

                                        # name tname and type(= name of the current construct)

                                }

                        }

			&ScopeClosed;

             		next;

     		}

                #

                # handle function pointers

                #

                if($line =~ /$rgxfptr/)

                {

                        #print "Found function pointer === $line \n";

                        &PrepareKwdString(";\$");

                        &DoDelegates;

                        next;

                }

     		#

     		# simple structs, enums have already been handled above, handle their typedefs now

     		# has to be after typedef fptr TODO: later on move the typedef fptr handling to

     		# DoTypedefs like typedef struct/union/enum

     		#

     		if($line =~ /$rgxtpdef/)

     		{

                	&PrepareKwdString("^{|{\$|;\$");

                       	&DoTypeDefs;

              		next;

     		}

     		#

     		# handle functions

     		#

		if($line =~ /$rgxfunction/)

                {

        		&PrepareKwdString("^{|{\$|;\$");

        		# paranthesis can appear in statements such as if,else if,switch

        		# so skip these

        		if($keywdstring !~ /^if|^else|^switch|^return/)

        		{

        			&DoFunctions;

        		}

                        next;

                }

                if($line =~ /$rgxdata/)

                {

                          &PrepareKwdString(";\$|{\$|^{");

                          &DoData;

                          next;

                }



		if($line =~ /$rgxenumconsts/) #enum consts spanning multiple lines,not handled?

		{

			&DoEnumConsts;

			next;

		}



                if($line =~ /{/)

     		{

			&ScopeOpened;

             		next;

     		}

   	}

}



sub PrepareKwdString

{

        my ($delim) = @_;

        while(($line ne NULL) && ($line !~ /$delim/))

        {

                $index = $index + 1; # move one record ahead

                $line = $FileStream[$index];

           	$line =~ s/^\s*//g;

           	$line =~ s/\s*$//g;

           	chomp $line;

           	$keywdstring = $keywdstring." ".$line;

        }

# TODO : this assumes that last character is always a { or ; i.e { ; are not allowed in the middle

# any workaround ?

        # store last character i.e ; or { in \$lastdelimiter for future refernce

        $lastdelimiter = chop($keywdstring);

        $keywdstring = $keywdstring.$lastdelimiter;

        if($lastdelimiter eq "{")

        {

                &ScopeOpened;

        }

        @fields = split /\s+/, $keywdstring;

        1;

}



sub ScopeOpened

{

	# this mark the beginning of some scope i.e namespace,class,enum or function definition

        # or any other blocks (if,else,properties etc.)

        ++$scope;

        push(@scopes,$scope);

        push(@Hashes,"duumy");

	1;

}



sub ScopeClosed

{

	# this mark the end of some scope i.e namespace,class,enum or function definition

        # or any other blocks (if,else,properties etc.)

        --$scope;

#        if($scope == 0) # scope end, nothing more to reset

#        {

#                $namespace = "DEFAULT";

#        }

        # update $name,$state

        my $ignore = pop(@scopes);  # ignore topmost \$elem for which the scope has been closed.

        my $elem = pop(@scopes);    # get name,state for previous scope

        if($elem =~ /:/)            # was a class,struct,enum scope

        {

         	($state,$name) = split /:/,$elem;

        }

        else  # was a function or property definition

        {

               	$state = 0;

        	$name = undef;

        }

        push(@scopes,$elem);

        

        # update $hash

 	$ignore = pop(@Hashes);

        my $h = pop(@Hashes);

        if($h eq "dummy")

        {

                $hash = undef;

        }

        else

        {

                $hash = $h;

        }

        push(@Hashes,$hash);

	1;

}



sub DoDirectives

{

        if($keywdstring =~ /\w+(\/\w+)*\.h/)

        {

              my $drname = $&;	#last matched pattern

              push(@Directives,$drname);

        }

          1;

}



sub DoNameSpace

{

        return if($state!=1 && $state !=0);

        my ($n,$namesps);

        if($state == 1)

        {

                # handling for namespace inside namespace,

                # get the current parent hash from $hash

                if( ref($hash) ne "HASH" )

                {

                        die "ERROR: Did not find parent hash reference in \$hash \n";

                }

                $n = $hash;

                if(!defined $n->{NAMESPACES})

                {

                        $n->{NAMESPACES} = {}; # hash of namespaces nested inside onother namespace

                }

                $namesps = \%{$n->{NAMESPACES}};

        }

        else

        {

                $namesps = \%NameSpaces;

        }

        my $current = $fields[1];

        $current =~ s/\{.*//;	# remove unwanted characters

	if(! exists $namesps{$current}) # for scattered namespaces

	{

                $namesps{$current} = {};

        	$namesps{$current}{NAME} = $current;

	}

        $name = $current;

        $state = 1;

        my $scopeno = pop(@scopes);

        my $str = $state.':'.$name.':'.$scopeno;

        push(@scopes,$str);

        $hash = \%{$namesps->{$name}};

        $ignore = pop(@Hashes);

        push(@Hashes,$hash);

        1;

}



sub DoClass

{

        return if($state!=2 && $state != 1 && $state!=0);

        my ($n,$classes);

        if($state == 1 or $state == 2)

        {

                # handling for class inside a namespace or class

                # get the current parent hash from $hash

                if( ref($hash) ne "HASH" )

                {

                        die "ERROR: Did not find parent hash reference in \$hash \n";

                }

                $n = $hash;

                if(!defined $n->{CLASSES})

                {

                        $n->{CLASSES} = {}; # hash of classes nested inside a namespace or onother class

                }

                $classes = \%{$n->{CLASSES}};

        }

        else

        {

                $n = \%NameSpaces;

                if(!defined $n->{$namespace}{CLASSES})

                {

                	$n->{$namespace}{CLASSES} = {}; # hash of classes in the global/default namespace

                }

                $classes = \%{$n->{$namespace}{CLASSES}};

        }

	my ($kwdright,@classstrarr,$classstr,$qualifiers);

        if($keywdstring =~ /^class/)

        {

                $kwdright = $';

                $kwdright =~ s/{//g;

              	if($kwdright =~ /:/)

        	{

                       $classstr = $`;

        	}

        	else

        	{

                       $classstr = $kwdright;

        	}

                $classstr =~ s/^\s*//g;

                @classstrarr = split /\s+/, $classstr;

                $name = pop(@classstrarr);

# TODO: qualifiers for class like DLL_Export??

                $qualifiers = join (' ',@classstrarr);

                

                if(exists $classes->{$name})

        	{

        		die "ERROR: Class $name multiply defined in Namespace $namespace";

        	}

                $classes->{$name} = {};

        	$classes->{$name}{NAME} = $name;

        	if($kwdright =~ /:/)

        	{

        		$classes->{$name}{ISDERIVED} = 1;

        		$classes->{$name}{MYBASE} = [];

        		my $basestr = $'; #right string of last pattern match

        		$basestr =~ s/,/ /g;

        		$basestr =~ s/\{.*//g;

                        # remove all leading space chars if any

                        # this seems to be a problem which should be taken care of everywhere

                        # split doesnot covers starting space characters for spliting

        		$basestr =~ s/^\s*//g;

        		my @bases = split /\s+/, $basestr;

        		my $i=0;

        	  	while ($bases[$i])

        	  	{

                                push (@{$classes->{$name}{MYBASE}} , $bases[$i].' '.$bases[$i+1]);

                                $i =$i+2;

        		}

               }

     }

       $state = 2;

       my $scopeno = pop(@scopes);

       my $str = $state.':'.$name.':'.$scopeno;

       push(@scopes,$str);

       $hash = \%{$classes->{$name}};

       $ignore = pop(@Hashes);

       push(@Hashes,$hash);

}



sub DoStruct

{

        return if($state !=1 && $state !=2 && $state !=3 && $state !=0);

        my ($n,$structs);

        if($state == 1 or $state == 2 or $state == 3)

        {

                # handling for structs inside namespace,class,onother struct

                # get the current parent hash from $hash

                if( ref($hash) ne "HASH" )

                {

                        die "ERROR: Did not find parent hash reference in \$hash \n";

                }

                $n = $hash;

                if(!defined $n->{STRUCTS})

                {

                        $n->{STRUCTS} = {};# hash of structs in the class

                }

                $structs = \%{$n->{STRUCTS}};

        }

        else

        {

                $n = \%NameSpaces;

                if(!defined $n->{$namespace}{STRUCTS})

                {

                	$n->{$namespace}{STRUCTS} = {}; # hash of structures in the global/default namespace

                }

                $structs = \%{$n->{$namespace}{STRUCTS}};

        }

	my ($kwdright,@kwdrightarr);

        if($keywdstring =~ /^struct/)

        {

                $kwdright = $';

                $kwdright =~ s/^\s*//g;

                @kwdrightarr = split /\s+/, $kwdright;

                if($kwdrightarr[0] !~ /\w+/)

                {

		# Special Handling NOTE #

                # Handling for struct declarations(not definitions) without names of the form

                # struct { int X,..}var;

                # Since intention here is to use this struct definition for once (that's why

                # it has no name) so logically we should not store this as a definition in our

                # STRUCTS(atleast for now.. when we are not parsing variable declarations)

                # but still we'll store their definitions with a unique name

                # We inlclude a unique string as the struct name for such structs,

                # given by concatenation of the string "StructNoName" and a number equal to the

                # current value of $dummycounter.

                # $dummycounter is incremented with each such struct encountered

                        $dummycounter++;

                        $name = "StructNoName".$dummycounter;

                }

                else

                {

                	$name = $kwdrightarr[0];

	        	$name =~ s/:.*//;

        		$name =~ s/\{.*//;	#remove unwanted characters

		}

                if(exists $structs->{$name})

        	{

        		die "ERROR: Struct $name multiply defined in Namespace $namespace";

        	}

                $structs->{$name} = {};

        	$structs->{$name}{NAME} = $name;

	}

        $state = 3;

        my $scopeno = pop(@scopes);

        my $str = $state.':'.$name.':'.$scopeno;

        push(@scopes,$str);

        $hash = \%{$structs->{$name}};

        $ignore = pop(@Hashes);

        push(@Hashes,$hash);

}





sub DoEnum

{

        return if($state !=1 && $state !=2 && $state !=3 && $state !=0);

        my ($n,$enums);

        if($state == 1 or $state == 2 or $state == 3)

        {

                # handling for enums inside a namespace,class or a struct

                # get the current parent hash from $hash

                if( ref($hash) ne "HASH" )

                {

                        die "ERROR: Did not find parent hash reference in \$hash \n";

                }

                $n = $hash;

                if(!defined $n->{ENUMS})

                {

                        $n->{ENUMS} = {};

                }

                $enums = \%{$n->{ENUMS}};

        }

        else

        {

                $n = \%NameSpaces;

                if(!defined $n->{$namespace}{ENUMS})

                {

                	$n->{$namespace}{ENUMS} = {};# hash of enums in the global/default namespace

                }

                $enums = \%{$n->{$namespace}{ENUMS}};

        }

	my ($kwdright,@kwdrightarr);

        if($keywdstring =~ /^enum/)

        {

                $kwdright = $';

                $kwdright =~ s/^\s*//g;

                @kwdrightarr = split /\s+/, $kwdright;

		if($kwdrightarr[0] !~ /\w+/)

                {

			# Special Handling NOTE #

                        # Handling for enums without names.We inlclude a unique string as the

                        # enum name for such enums,given by concatenation of the string

                        # "EnumNoName" and a number equal to the the current value of $dummycounter.

                        # $dummycounter is incremented with each such enum encountered

                        $dummycounter++;

                        $name = "EnumNoName".$dummycounter; 

                }

                else

                {

                	$name = $kwdrightarr[0];

	        	$name =~ s/:.*//;

        		$name =~ s/\{.*//;	#remove unwanted characters

		}

                if(exists $enums->{$name})

        	{

        		die "ERROR: Enum $name multiply defined in Namespace $namespace";

        	}

                $enums->{$name} = {};

        	$enums->{$name}{NAME} = $name;

       }

        $state = 4;

        my $scopeno = pop(@scopes);

        my $str = $state.':'.$name.':'.$scopeno;

        push(@scopes,$str);

        $hash = \%{$enums->{$name}};

        $ignore = pop(@Hashes);

        push(@Hashes,$hash);

}





sub DoTypeDefs

{

        return if($state !=1 && $state !=2 && $state !=3 && $state !=0);

       	my ($n,$typedefs);

        if($state == 1 or $state == 2 or $state == 3)

        {

                # handling for typedefs inside a namespace,class,struct

                # get the current parent hash from $hash

                if( ref($hash) ne "HASH" )

                {

                        die "ERROR: Did not find parent hash reference in \$hash \n";

                }

                $n = $hash;

                if(!defined $n->{TYPEDEFS})

                {

                        $n->{TYPEDEFS} = {};

                }

                $typedefs = \%{$n->{TYPEDEFS}};

        }

        else

        {

                $n = \%NameSpaces;

                if(!defined $n->{$namespace}{TYPEDEFS})

                {

                	$n->{$namespace}{TYPEDEFS} = {};

                }

                $typedefs = \%{$n->{$namespace}{TYPEDEFS}};

        }

        my ($kwdright,@kwdrightarr);

        my $rgxtypedef = "typedef\\s+(enum|struct|union)";

        if($keywdstring =~ /$rgxtypedef/)

        {

                $kwdright = $';

                $kwdright =~ s/^\s*//g;

                @kwdrightarr = split /\s+/, $kwdright;

                if($kwdrightarr[0] !~ /\w+/)

                {

                        $dummycounter++;

                        $name = "TypeDefNoName".$dummycounter;

                }

                else

                {

                	$name = $kwdrightarr[0];

                	$name =~ s/:.*//;

                	$name =~ s/\{.*//;	#remove unwanted characters

                }

                if($keywdstring =~ /struct/)

                {

                        # handle struct type definition only, for now

                        if($lastdelimiter eq '{')

                        {

                                if(!defined $typedefs->{STRUCTS})

                                {

                                        $typedefs->{STRUCTS} = {};

                                }

                                $tstructs = \%{$typedefs->{STRUCTS}};

                                if(exists $tstructs->{$name})

                	        {

                		      die "ERROR: typedef Struct $name multiply defined in Namespace $namespace";

                        	}

                                $tstructs->{$name} = {};

                	        $tstructs->{$name}{NAME} = $name;

                                $state = 5;

                                my $scopeno = pop(@scopes);

                                my $str = $state.':'.$name.':'.$scopeno;

                                push(@scopes,$str);

                                $hash = \%{$tstructs->{$name}};

                                $ignore = pop(@Hashes);

                                push(@Hashes,$hash);

        	        }

                }

                elsif($keywdstring =~ /enum/)

                {

                        # handle enum type definition only,for now

                        if($lastdelimiter eq '{')

                        {

                                if(!defined $typedefs->{ENUMS})

                                {

                                        $typedefs->{ENUMS} = {};

                                }

                                $tenums = \%{$typedefs->{ENUMS}};

                                if(exists $etnums->{$name})

                	        {

                		      die "ERROR: typedef Enum $name multiply defined in Namespace $namespace";

                               	}

                                $tenums->{$name} = {};

                        	$tenums->{$name}{NAME} = $name;

                        	$state = 6;

                                my $scopeno = pop(@scopes);

                                my $str = $state.':'.$name.':'.$scopeno;

                                push(@scopes,$str);

                                $hash = \%{$tenums->{$name}};

                                $ignore = pop(@Hashes);

                                push(@Hashes,$hash);

                	}

                }

                elsif($keywdstring =~ /union/)

                {

                        # handle union type definition only,for now

                        if($lastdelimiter eq '{')

                        {

                                if(!defined $typedefs->{UNIONS})

                                {

                                        $typedefs->{UNIONS} = {};

                                }

                                $tunions = \%{$typedefs->{UNIONS}};

                                if(exists $tunions->{$name})

                	        {

                		      die "ERROR: typdef Union $name multiply defined in Namespace $namespace";

                               	}

                                $tunions->{$name} = {};

                        	$tunions->{$name}{NAME} = $name;

                        	$state = 7;

                                my $scopeno = pop(@scopes);

                                my $str = $state.':'.$name.':'.$scopeno;

                                push(@scopes,$str);

                                $hash = \%{$tunions->{$name}};

                                $ignore = pop(@Hashes);

                                push(@Hashes,$hash);

                	}

                }

        }

        else

        {

                # TODO: Do nothing for now for other typedefs

        }

        1;

}



sub DoEnumConsts

{

	return if($state != 4 && $state != 6);

        # get the current parent property hash from \$hash

        if( ref($hash) ne "HASH" )

        {

                die "ERROR: Did not find parent hash reference in \$hash \n";

        }

        my $t = $hash;

        if(!defined $t->{ENUMCONSTS})

        {

                $t->{ENUMCONSTS}= ();# array of enum constants definitions

        }

        if($keywdstring =~ /$rgxenumconsts/) # regular expression for enum constant

        {

		my $econsts = \@{$t->{ENUMCONSTS}};

		my $ecstr = $keywdstring;

		my @enumconsts = split /\,/,$ecstr;

		my ($i,$ec,@found,@tarr,$temp);

		for($i=0;$i<@enumconsts;$i++)

		{

			$ec = $enumconsts[$i];

			#remove leading and trailing space characters

			$ec =~ s/^\s*//g;

			$ec =~ s/\s*$//g;

#code for treating enum constant as a array

			if($ec)

			{

				push(@{$econsts},$ec);

			}



#code for treating enum constant as a hash

			#@tarr = split(/\=/,$ec);

			#$temp = join(' ',@tarr);

			#@found = split(/\s+/,$temp);

			#if(scalar @found)

			#{

			#	$econsts->{$found[0]} = $found[1];

			#}

		}

	}

	1;

}



sub DoFunctions

{

        return if($state != 1 && $state !=2 && $state !=3 && $state!=0);

        my ($t,$functs);

        if($state == 1 or $state == 2 or $state == 3)

        {

        	# get the current parent(class/struct/interface) hash from \$hash

	        if( ref($hash) ne "HASH" )

        	{

                	die "ERROR: Did not find parent hash reference in \$hash \n";

	        }

        	$t = $hash;

	        if(!defined $t->{FUNCTIONS})

        	{

        		$t->{FUNCTIONS} = {};# hash of function definitions

        	}

		$functs = \%{$t->{FUNCTIONS}};



        }

	else

        {

                 $t= \%{$NameSpaces{$namespace}{GLOBALS}};

                 if(!defined $t->{FUNCTIONS})

                 {

                         $t->{FUNCTIONS} = {};# hash of function definitions

                 }

                 $functs = \%{$t->{FUNCTIONS}};

        }

        my ($kwdleft,$kwdright,@kwdleftarr,@kwdrightarr);

        my ($dummy,$rettype,$fname,@tarr);

        if($keywdstring =~ /\(.*\)/) # regular expression for function definition

        {

                $kwdleft = $`;

                $kwdright = $';

                $kwdleft =~ s/^\s*//g;

                $kwdright =~ s/^\s*//g;

                @kwdleftarr = split /\s+/, $kwdleft;

                @kwdrightarr = split /\s+/, $kwdright;



                @tarr  = @kwdleftarr;

                # pop out function name , return type and access specifier

                $fname = pop(@tarr);

                if(($fname ne $name) && ($fname ne '~'.$name))

                {

			my $type = pop(@tarr);

			# handle return of pointer and references

			# treat them as part of return type.

                        # TODO: handle multiple * or &. while loop instead of if?

			if(($type eq "*") or ($type eq "&"))

			{

				my $ret = pop(@tarr);

				$type = $ret.$type;

			}

			$rettype = $type;

                }

                #$dummy = shift(@tarr); # handle cases such as public: int f();

                # tarr now contains only function specifiers if any

                my @specifiers = @tarr;

                my $fid = $fname;	# id for function lookup

                my @params;

                # match first \) since ctors for derived classes may include statements as :base \(\)

# TODO : Take care of the ctros for derived classes

                if( $keywdstring =~ /\(.+?\)/ )	#if line contains some params or <space> chars

                {

                        my $prmstr = $&;	#last matched pattern

                        $prmstr =~ s/\(//;$prmstr =~ s/\)//;

                        @params = split /,/, $prmstr;

                        # loop and get all types use in params for making function identity

                        my (@found,$type,$ident,$tmpstring,$typestr,$loop);

                        while($params[$loop])

                        {

                                $params[$loop] =~ s/^\s*//g;

                                @found = split /\s+/, $params[$loop];

                                $ident = pop(@found);

                                $tmpstring = join(':',@found);

                                $typestr = $typestr.":".$tmpstring;

                                $loop = $loop + 1;

                        }

                        $fid = $fid.$typestr;

                }

                $functs->{$fid}{NAME} = $fname;

                $functs->{$fid}{TYPE} = $rettype;

                # get access from member states

                my $acc = $access;

                if($acc eq "DEFAULT")

                {

                        if($state == 1)

                        {

                                $acc = "private"; # default access is private for class

                        }

                        else

                        {

                                $acc = "public"; # default access is public for structures

                        }

                }



                $functs->{$fid}{ACCESS} = $acc;

                if($fname eq $name) # set ISCTOR if constructor found

                {

                        $functs->{$fid}{ISCTOR} = 1;

                        # TODO: include handling for :base construct here

                }

                my $dtr = '~'.$name;

		if($fname eq $dtr) # set ISDTOR if destructor found

		{

                        $functs->{$fid}{ISDTOR} = 1;

		}



                $functs->{$fid}{PARAMS} = [];

                $functs->{$fid}{SPECIFIERS} = [];

                my $l = 0;

                while($specifiers[$l])

                {

                        push (@{$functs->{$fid}{SPECIFIERS}}, ($specifiers[$l]));

                        $l = $l + 1;

                }

                $l = 0;

                my (@found,$type,$paramname,$qualifiers);

                while($params[$l])

                {

                        $params[$l] =~ s/^\s*//g;

                        @found = split /\s+/, $params[$l];

                        $paramname = pop(@found);

                        $type = pop(@found);

                        $qualifiers = join(' ',@found);

                        push (@{$functs->{$fid}{PARAMS}},{NAME,$paramname,TYPE,$type,QUALIFIERS,$qualifiers});

                        $l = $l + 1;

                }

       }

       if($lastdelimiter eq '{') # create state for function definitions

       {

                $name = $fname;

                $state = 8;

                my $scopeno = pop(@scopes);

                my $str = $state.':'.$name.':'.$scopeno;

                push(@scopes,$str);

                $hash = \%{$functs->{$name}};

                $ignore = pop(@Hashes);

                push(@Hashes,$hash);

       }

       1;

}





sub DoDelegates

{

        return if($state !=1 && $state !=2 && $state !=3 && $state !=0);

        my ($n,$delegates);

        if($state == 1 or $state ==2 or $state ==3)

        {

                # handling for delegates inside a namespace/class/struct

                # get the current parent hash from $hash

                if( ref($hash) ne "HASH" )

                {

                        die "ERROR: Did not find parent hash reference in \$hash \n";

                }

                $n = $hash;

                if(!defined $n->{DELEGATES})

                {

                        $n->{DELEGATES} = {}; # hash of delegate definitions

                }

                $delegates = \%{$n->{DELEGATES}};

        }

        else

        {

                $n = \%{$NameSpaces{$namespace}{GLOBALS}};

                if(!defined $n->{DELEGATES})

                {

                	$n->{DELEGATES} = {}; # hash of delegate definitions in global/default namespace

                }

                $delegates = \%{$n->{DELEGATES}};

        }

        # ensure that change in global regex does not affect the backreference handling below

        if($keywdstring =~ /$rgxfptr/)

        {

                my ($rettype,$delgname,$prmstr);

                $rettype = $2;

                $delgname = $8;

                $prmstr = $9;

                $rettype =~ s/\s*//g; # remove all spaces from rettype

                my @params = split /,/, $prmstr;

                if(exists $n->{DELEGATES}{$delgname})

                {

        		die "ERROR: function pointer $delgname multiply defined";

	        }

                $delegates->{$delgname}{NAME} = $delgname;

                $delegates->{$delgname}{TYPE} = $rettype;

                

                my $acc = $access;

                if($acc eq "DEFAULT")

                {

                        if($state == 1)

                        {

                                $acc = "private"; # default access is private for class

                        }

                        else

                        {

                                $acc = "public"; # default access is public for structures

                        }

                }

                $delegates->{$delgname}{ACCESS} = $acc;

                $delegates->{$delgname}{PARAMS} = [];

                my $l = 0;

		my (@found,$type,$typesuffix,$paramname,$qualifiers,@suffixs,@tmp);

                while($params[$l])

                {

                        $rgxparamdef = "(($rgxqualifiers\\s+)*($rgxtype)(\\s+(\\w+))?)";

                        if($params[$l] =~ /$rgxparamdef/)

                        {

                                $qualifiers = $3;

                                $type = $4;

                                $paramname = $11;

                                $type =~ s/\s*//g; # remove all spaces from the type

                                push (@{$delegates->{$delgname}{PARAMS}},{NAME,$paramname,TYPE,$type,QUALIFIERS,$qualifiers});

                        }

                        $l = $l + 1;

                }

        }

        1;

}



sub DoData

{

        return if($state !=2 && $state !=3 && $state !=5);

        # get the current parent(class/struct) hash from \$hash

        if( ref($hash) ne "HASH" )

        {

                die "ERROR: Did not find parent hash reference in \$hash \n";

        }

        my $t = $hash;

        if(!defined $t->{DATA})

        {

        	$t->{DATA} = {};# hash of data definitions

        }

        

        my ($acc,$spec,$dtype,$dname,@temp);

        if($keywdstring =~ /$rgxdata/)

 	{

                @temp = split /\s+/, $1;

                $dname = pop(@temp);

                $dtype = pop(@temp);

                my $acc = $access;

                if($acc eq "DEFAULT")

                {

                        if($state == 1)

                        {

                                $acc  = "private"; # default access is private for class

                        }

                        else

                        {

                                $acc  = "public"; # default access is public for structures

                        }

                }

                # array \@temp now contains qualifier's and/or modifiers if any

                $spec = join(' ',@temp);

# TODO : Place similar checks at other places as well

                #if(! defined $Types{$dtype})

                #{

                #	die "ERROR:$Types{int} Use of undefined type $dtype with data definition of $dname";

                #}

                if(exists $t->{DATA}{$dname})

                {

                        die "ERROR: DATA $dname multiply defined";

                }

                $data = \%{$t->{DATA}{$acc}};

                $data->{$dname}{NAME} = $dname;

                $data->{$dname}{TYPE} = $dtype;

                $data->{$dname}{ACCESS} = $acc;

                $data->{$dname}{QUALIFIERS} = $spec;

        }

        1;

}



sub PointsToRemember

{

        # local variables are used for reseting global variables for this scope

        # my variables are actually the local variables which are used within this scope

        # default namespace name is DEFAULT

	# Quantifiers such as '*' and '+' are "greedy". I.e. they match as much as they can,

	# not as few, ? is used to match the first thingy

	# The meta characters '\b' and '\B' are used for testing word boundaries & non-word boundaries.

	# E.g. $line =~ /\bclass/ Now, it only finds "class" if it starts at a word boundary,not inside a word.

}



sub DumpDatastructures

{

print <<EOF

Perl Data Structure Summary:



----------------------------------------------------------------------------------------------

DIRECTIVES : Directive statements are in an array \@Directives

----------------------------------------------------------------------------------------------

        Each element of the array is the name of a directive(using for C#) encountered.



----------------------------------------------------------------------------------------------

NAMESPACES : Namespace definitions are in a hash \%NameSpaces{}, indexed by namespace name

----------------------------------------------------------------------------------------------

        Each namespace definition is a hash reference, with the following fields:

        \$NameSpaces{\$namespace}{NAME}		     namespace name, e.g. ImageEditing

        \$NameSpaces{\$namespace}{CLASSES}           hash of class definitions

        \$NameSpaces{\$namespace}{ENUMS}             hash of enum definitions

        \$NameSpaces{\$namespace}{STRUCTS}           hash of struct definitions

        \$NameSpaces{\$namespace}{GLOBALS}           hash of Functions,Data definitions etc.



----------------------------------------------------------------------------------------------

CLASSES : Take %Classes = %{$NameSpaces{$namespace}{CLASSES}}

----------------------------------------------------------------------------------------------

        Each class definition is a hash reference, with the following fields:

        \$Classes{\$name}{NAME}                      name, e.g. Value

        \$Classes{\$name}{ACCESS}                    access specifier for the class

        \$Classes{\$name}{TYPE}                      class type. e.g partial,abstract etc.

        \$Classes{\$name}{ISBASE}                    is a base class

        \$Classes{\$name}{ISDERIVED}	             is a derived class

        \$Classes{\$name}{ISABSTRACT}                is an abstract class

        \$Classes{\$name}{MYBASE}	             array of bases(along with access specifier)

                                                     (<access> name, <access> name ..)

        \$Classes{\$name}{DATA}	                     hash of data definitions

        \$Classes{\$name}{FUNCTIONS}	             hash of function definitions

        \$Classes{\$name}{DELEGATES}                 hash of delegate definitions

        \$Classes{\$name}{EVENTS}                    hash of event definitions.

        

        \$Classes{\$name}{CLASSES}                   hash of nested class definitions

        \$Classes{\$name}{ENUMS}                     hash of nested enum definitions

        \$Classes{\$name}{STRUCTS}                   hash of nested struct definitions

----------------------------------------------------------------------------------------------

DATA : Take %Data = %{$NameSpaces{$namespace}{CLASSES}{\$name}{DATA}}

----------------------------------------------------------------------------------------------

        Each data definition is a hash reference, with the following fields:

        \$Data{\$dataname}{NAME}		     name of the data variable

        \$Data{\$dataname}{TYPE}	             datatype of the variable

        \$Data{\$dataname}{ACCESS}		     access specifier for the data

        \$Data{\$dataname}{QUALIFIERS}               string of qualifier(s) and modifier(s)

                                                     for the data i.e static, unsigned,const,

                                                     volatile etc.



----------------------------------------------------------------------------------------------

FUNCTIONS : Take %Functions = %{$NameSpaces{$namespace}{CLASSES}{\$name}{FUNCTIONS}}

----------------------------------------------------------------------------------------------

        Each function definition is a hash reference, with the following fields:

        \$Functions{\$functID}{NAME}		    name of the function

        \$Functions{\$functID}{TYPE}		    return type of the function

        \$Functions{\$functID}{ACCESS}	            access specifier for the function

        \$Functions{\$functID}{PARAMS}              list of function parameters i.e

        					    list of pairs (type name)

        \$Functions{\$functID}{SPECIFIERS}	    list of function specifiers e.g

               					    inline,virtual,static,friend

Here \$functID is a unique function identifier of the form functionname:param1_type:param2_type:..



Each %Params = \$Functions{\$functID}{PARAMS} is again a hash with following fields

        \$Params{$paramname}{NAME}                 name of the data variable

        \$Params{$paramname}{TYPE}                 datatype of the variable

        \$Params{$paramname}{REF}                  is a reference parameter

        \$Params{$paramname}{PTR}                  is a pointer type parameter

        \$Params{$paramname}{QUALIFIERS}           string of qualifier(s) and modifier(s)

                                                   for the data i.e static, unsigned,const,

                                                   volatile etc.



----------------------------------------------------------------------------------------------

DELEGATES : Take %Delegates = %{$NameSpaces{$namespace}{CLASSES}{\$name}{DELEGATES}}

----------------------------------------------------------------------------------------------

        Each delegate definition is a hash reference, with the following fields:

        \$Delegates{\$delname}{NAME}		   name of the delegate

        \$Delegates{\$delname}{TYPE}		   return type of the delegate

        \$Delegates{\$delname}{ACCESS}	           access specifier for the delegate

        \$Delegates{\$delname}{PARAMS}	           list of delegate parameters i.e

               				           list of pairs (type name)

Each %Params = \$Delegates{\$delname}{PARAMS} is again a hash with fields as given above for

functions.



----------------------------------------------------------------------------------------------

EVENTS : Take %Events = %{$NameSpaces{$namespace}{CLASSES}{\$name}{EVENTS}}

----------------------------------------------------------------------------------------------

        Each event definition is a hash reference, with the following fields:

        \$Events{NAME}		                  name of the delegate

        \$Events{TYPE}		                  return type of the delegate

        \$Events{ACCESS}	                  access specifier for the delegate

        \$Events{PARAMS}	                  list of delegate parameters i.e

        					  list of pairs (type name)



----------------------------------------------------------------------------------------------

PROPERTIES : Take %Properties = %{$NameSpaces{$namespace}{CLASSES}{\$name}{PROPERTIES}}

----------------------------------------------------------------------------------------------

        Each property definition is a hash reference, with the following fields:

        \$Properties{NAME}		          name of the property

        \$Properties{VARIABLE}	                  variable name to which the property belongs

        \$Properties{ACCESS}	                  access specifier for the property

        \$Properties{TYPE}	                  return type of the property

        \$Properties{ISGETTER}	                  is a getter property ?

        \$Properties{ISSETTER}                    is a setter property ?

        \$Properties{GETACCESS}                   access specifier for get if isgetter

        \$Properties{SETACCESS}                   access specifier for set if issetter



----------------------------------------------------------------------------------------------

STRUCTS : Take %Structs= %{$NameSpaces{$namespace}{STRUCTS}}

----------------------------------------------------------------------------------------------

Each struct definition is a hash reference, similar to class definition.



----------------------------------------------------------------------------------------------

ENUMS : Take %Enums= %{$NameSpaces{$namespace}{ENUMS}}

----------------------------------------------------------------------------------------------

        Each enum definition is a hash reference, with the following fields:

        \$Enums{\$name}{NAME}                      name, e.g. Value

        \$Enums{\$name}{ACCESS}                    access specifier for the enum

        \$Enums{\$name}{ENUMCONSTS}	           hash of enum constants



----------------------------------------------------------------------------------------------

GLOBALS : Take %Globals= %{$NameSpaces{$namespace}{GLOBALS}}

----------------------------------------------------------------------------------------------

        GLOBALS is a hash , with the following fields:

        \$Globals{\$name}{FUNCTIONS}                 hash of global function definitions

        \$Globals{\$name}{DATA}	                     hash of global data definitions

        \$GLOBALS{\$name}{DELEGATES}                 hash of global delegate definitions

        

EOF

}



# EOF
