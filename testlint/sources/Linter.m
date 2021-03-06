/*
 
 Erica Sadun, http://ericasadun.com
 
 */

#import "Linter.h"
#import "Utility.h"
#import "NSArray+Frankenstein.h"
#import "RegexHelper.h"

@implementation Linter
{
    NSMutableDictionary *uidStrings;
}

#pragma mark - Init

- (instancetype) init
{
    if (!(self = [super init])) return self;
    _encounteredErrors = NO;

    _skipStyleChecks = NO;
    _skipHygieneChecks = NO;
    _enableUnwrapAndForcedCastCheck = YES;
    _enableAnalRetentiveColonCheck = YES;
    _enableAllmanCheck = YES;
    
    _enableSingleLineBraceAbuseCheck = NO;

    // Many false positives
    _enableAccessModifierChecks = NO;
    _enableConstructors = NO;

    return self;
}

#pragma mark - Delintage

- (void) lint: (NSString *) path
{
    NSString *string = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!string) return;
    
    BOOL topLevel = [string containsString:@"@UIApplicationMain"];
    
    // I have some files that are purely generic type stuff and access checks kills 'em
    BOOL skipAccessCheckForFile = [string containsString:@"##SkipAccessChecksForFile"];

    // Splinter into lines
    NSArray *lines = [string componentsSeparatedByString:@"\n"];
    
    int count = 0;
    int cautions = 0;
    int warnings = 0;
    
    // In shell build phases you can write to stderr using the following format:
    // <filename>:<linenumber>: error | warn | note : <message>\n
    
    for (NSString *eachLine in lines)
    {
        ++count;
        NSString *line = eachLine;
        
        // META PROCESSING
        // This material is always active and should never be overridden by command-line parameters
        {
            // No worries, mate! Skip any line with nwm
            if ([RegexHelper testString:@"nwm" inString:line]) continue;
            
            // Convert all FIXMEs to warnings
            if ([RegexHelper testString:@"FIXME" inString:line])
            {
                ++warnings;
                Log(@"%@:%zd: warning: Line %zd is broken", path, count, count);
                Log(@"%@", line);
            }
            else if ([RegexHelper testString:@"NOTE: " inString:line])
            {
                NSRange range = [line rangeOfString:@"NOTE: "]; // should always be found
                NSString *remaining = [line substringFromIndex:range.location];
                Log(@"%@:%zd: note: Line %zd : %@", path, count, count, remaining);
                Log(@"%@", line);
            }
            else if ([RegexHelper testString:@"WARNING: " inString:line])
            {
                NSRange range = [line rangeOfString:@"WARNING: "]; // should always be found
                NSString *remaining = [line substringFromIndex:range.location];
                Log(@"%@:%zd: warning: Line %zd : %@", path, count, count, remaining);
                Log(@"%@", line);
            }
            else if ([RegexHelper testString:@"ERROR: " inString:line])
            {
                NSRange range = [line rangeOfString:@"ERROR: "]; // should always be found
                NSString *remaining = [line substringFromIndex:range.location];
                Log(@"%@:%zd: error: Line %zd : %@", path, count, count, remaining);
                Log(@"%@", line);
                _encounteredErrors = YES;
            }
            
            // AVOID FALSE PINGS ON COMMENTED LINES
            // Clip off trailing comments
            NSRange range = [line rangeOfString:@"// "];
            if (range.location != NSNotFound)
            {
                line = [line substringToIndex:range.location];
                
                // Also trims start of line, but that shouldn't be an issue for the following checks
                line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }
        
        // STYLE ISSUES
        if (!_skipStyleChecks)
        {
            /*

             This is another one that goes against personal taste.
             I much prefer spaces before and after colons for the most part (except
             in parameter lists, where I left associate with the label) but again
             consistency and peer pressure wins.

             */
            if (_enableAnalRetentiveColonCheck)
            {
                // Handle colons
                if ([RegexHelper testPattern:@"\\?\\s+\\S+\\s+:" inString:line])
                {
                    // ignore "? x : y" in ternary statements
                }
                else if ([RegexHelper testPattern:@"\\?\\s+:" inString:line])
                {
                    // ignore "? :" in ternary statements
                }
                else if ([RegexHelper testPattern:@"\\[\\S+\\s*:\\s+\\S+\\]" inString:line] ||
                         [RegexHelper testPattern:@"\\[\\S+\\s*:\\s+\\S+\\," inString:line])
                    //   [RegexHelper testPattern:@",\\s+\\S+\\s*:\\s+\\S+\\]" inString:line])
                {
                    // Tightening for dicts. Incomplete but enough to get you to the right lines
                    ++warnings;
                    Log(@"%@:%zd: warning: Line %zd uses loose spacing for likely Dictionary type declaration", path, count, count);
                }
                else if ([RegexHelper testPattern:@"\\s+\\:" inString:line])
                {
                    ++warnings;
                    Log(@"%@:%zd: warning: Line %zd uses a space before a colon", path, count, count);
                }
            }
            
            // Brace abuse checking defaults to NO
            if (_enableSingleLineBraceAbuseCheck)
            {
                if ([RegexHelper testPattern:@"\\{.*;.*\\}" inString:line])
                {
                    ++warnings;
                    Log(@"%@:%zd: warning: Excessive content in single-line scope", path, count, count);
                }
                
                /*

                 Excessive single-line brace length
                 I've disabled this for now, but I'm wavering back and forth on its value.
                 This would apply a maximum size check instead of existence check

                 */

                //        if ([RegexHelper testPattern:@"\\{.{80,}\\}" inString:line])
                //        {
                //            ++warnings;
                //            Log(@"%@:%zd: warning: Excessive content in single-line scope", path, count, count);
                //        }
            }
            
            /*

             True fact. I love 💗💗 Allman. It's the best for teaching and reading, not to mention the
             better cognitive load for general dev. However, I'm operating under external pressures.
             I have caved here.

             */
            
            if (_enableAllmanCheck)
            {
                // Allman
                if ([RegexHelper testPattern:@"^\\s*\\{" inString:line])
                {
                    ++warnings;
                    Log(@"%@:%zd: warning: Line %zd uses egregious Allman pattern. Welcome to Swift.", path, count, count);
                }
                
                if (![RegexHelper testString:@"#else" inString:line] &&
                    ([RegexHelper testPattern:@"^\\s*else" inString:line] ||
                     [RegexHelper testPattern:@"else\\s*$" inString:line]))
                {
                    ++warnings;
                    Log(@"%@:%zd: warning: Else case does not follow colinear 1TBS standard.", path, count, count);
                }
                
            }
        }
        
        // FILE HYGIENE
        if (!_skipHygieneChecks)
        {
            // Trailing whitespace on lines
            if ([RegexHelper testPattern:@"\\s+//.*\\S\\s+$" inString:line])
            {
                // ignore extra spaces on comment lines
            }
            else if ([RegexHelper testPattern:@"\\S\\s+$" inString:line])
            {
                ++warnings;
                Log(@"%@:%zd: warning: Line %zd includes trailing whitespace characters", path, count, count);
            }
        }
        
        // LANGUAGE ISSUES
        /*
         
         This is terrible with embedded functions (no access modifiers) and properties but it will generally start highlighting
         files that you haven't done a full access modifier audit on, so you know which items to buckle down on and fix. 
         Wouldn't it be great if Swift did this bit for you, basically when you say: "Make everything in this construct
         public that can be public" and then you can tweak down what you want to be internal and private.
         
         There are some implementation details such as no public modifiers for many generic details, so be aware of this going in.
         
         */
        
        // Access modifiers checks
        if (_enableAccessModifierChecks && !skipAccessCheckForFile)
        {
            if (!topLevel && [RegexHelper testPattern:@"^\\s*func" inString:line])
            {
                ++warnings;
                Log(@"%@:%zd: warning: Line %zd: No access modifier for func declaration", path, count, count);
            }

            // This does not seem to be catching things. Not sure why.
            if (!topLevel && [RegexHelper testPattern:@"^\\s*class\\s+func" inString:line])
            {
                ++warnings;
                Log(@"%@:%zd: warning: Line %zd: No access modifier for func declaration", path, count, count);
            }
            
            // Would also want access modifier checks for struct/class/enum properties
            // let or var is first item on line, must test against untrimmed version
            if ([eachLine hasPrefix:@"let"] ||
                [eachLine hasPrefix:@"var"])
            {
                ++warnings;
                Log(@"%@:%zd: warning: Line %zd: No access modifier for likely top-level variable assignment", path, count, count);
            }
            
            // Extensions must be on non-generic types
            if ([RegexHelper testPattern:@"extension\\s*\\S+\\s*:\\s*\\S+" inString:line])
            {
                // Does the class likely declare protocol conformance? If so, skip
            }
            else if ([RegexHelper testPattern:@"^\\s*extension" inString:line])
            {
                BOOL skip = NO;
                for (NSString *className in @[@"Array", @"ArraySlice", @"AutoreleasingUnsafeMutablePointer", @"BidirectionalReverseView", @"CFunctionPointer", @"ClosedInterval", @"CollectionOfOne", @"ContiguousArray", @"EmptyCollection", @"EmptyGenerator", @"GeneratorOf", @"GeneratorOfOne", @"HalfOpenInterval", @"RandomAccessReverseView", @"Range", @"RangeGenerator", @"Repeat", @"SequenceOf", @"Set", @"SetGenerator", @"SetIndex", @"SinkOf", @"StrideThrough", @"StrideThroughGenerator", @"StrideTo", @"StrideToGenerator", @"Unmanaged", @"UnsafeBufferPointer", @"UnsafeBufferPointerGenerator", @"UnsafeMutableBufferPointer", @"UnsafeMutablePointer", @"UnsafePointer"])
                {
                    NSString *check = [NSString stringWithFormat:@"extension\\s*%@",className];
                    if ([RegexHelper testPattern:check inString:line])
                        skip = YES;
                    
                }
                
                
                if (!skip)
                {
                    ++warnings;
                    Log(@"%@:%zd: warning: Line %zd: No access modifier for non-generic type extension", path, count, count);
                }
            }
        }
        
        
        // Check that -> return tokens point to Void and not () and that they are surrounded by spaces
        if ([RegexHelper testString:@"->=" inString:line]) {
            // Skip ->=
        } else if ([RegexHelper testPattern:@"->\\s*\\(\\)" inString:line]) {
            ++warnings;
            Log(@"%@:%zd: warning: Line %zd: Prefer Void as a return type over ()", path, count, count);
        } else if ([RegexHelper testPattern:@"->\\S" inString:line] ||
                   [RegexHelper testPattern:@"\\S->" inString:line]) {
            ++warnings;
            Log(@"%@:%zd: warning: Line %zd: leave spaces around the -> return token", path, count, count);
        }
        
        // Eliminate line-terminating semicolons
        if ([RegexHelper testPattern:@";\\s*$" inString:line])
        {
            ++warnings;
            Log(@"%@:%zd: warning: Line %zd: Swift does not require terminal semicolons except for statement separation", path, count, count);
        }
        
        // Elminate parentheses around if conditions
        if ([RegexHelper testPattern:@"if[\\s]*\\(" inString:line])
        {
            ++warnings;
            Log(@"%@:%zd: warning: Line %zd: Swift if statements do not require parentheses", path, count, count);
        }
        
        // Extraneous lets. For multi-line in-context scan, would test for ,\s*\n\s*let
        if ([RegexHelper testString:@"case" inString:line])
        {
            // do not test with case statements
        }
        else if ([RegexHelper testString:@"(.*let" inString:line])
        {
            // Skip lines that are likely tuple assignments in switch statements
        }
        else if ([RegexHelper testString:@", let" inString:line])
        {
            ++warnings;
            Log(@"%@:%zd: warning: Line %zd: Check for extraneous let usage in cascaded let", path, count, count);
//            ++cautions;
//            Log(@"%@:%zd: note: Line %zd: CAUTION: Check for extraneous let usage in cascaded let", path, count, count);
//            Log(@"%@", line);
        }
        
        // Limit use of forced unwrap and casts, however there are many cromulent reasons to
        // use these. Currently issued as warning rather than caution, but may downgrade or
        // offer forceChecksAreCautions option.
        if (_enableUnwrapAndForcedCastCheck)
        {
            if ([RegexHelper testString:@"as!" inString:line])
            {
                ++warnings;
                Log(@"%@:%zd: warning: Line %zd: Forced casts are generally unsafe", path, count, count);
            }
            else if ([RegexHelper testString:@"! " inString:line])
            {
                ++warnings;
                Log(@"%@:%zd: warning: Line %zd: Forced unwrapping is unsafe. Use let to conditionally unwrap where possible.", path, count, count);
            }
        }
        
        // Eliminate extraneous breaks in switch patterns other than in default statements
        // For multi-line in-context, should test for control-flow use of break
        
        if ([RegexHelper testPattern:@":\\s+break" inString:line])
        {
            // skip "case ...: break" cases
        }
        else if ([RegexHelper testString:@"{" inString:line] ||
                 [RegexHelper testString:@"}" inString:line])
        {
            // whitelist any break on a line with } or {
        }
        else if ((lines.count > (count + 1)) &&
                 [RegexHelper testString:@"}" inString:lines[count + 1]])
        {
            // whitelist any break is followed by a line with a }
        }
        else if ([RegexHelper testString:@"break" inString:line])
        {
            // was the previous line "default"?
            // this line is count - 1. previous line is count - 2
            if ((count - 2) > 0)
            {
                NSString *previousLine = lines[count - 2];
                if (![RegexHelper testString:@"default:" inString:previousLine])
                {
                    ++warnings;
                    Log(@"%@:%zd: warning: Line %zd: Swift cases do not implicitly fall through.", path, count, count);
                }
            }
        }
        
        // Test for .count == 0 and count() == 0 that might be better as isEmpty
        // Should this be a warning or a caution? May also catch mirror.count
        if ([RegexHelper testPattern:@"mirror" inString:line])
        {
            // Ignore any line that references mirrors.
        }
        else if ([RegexHelper testPattern:@"\\.count\\s*==\\s*0" inString:line] ||
                 [RegexHelper testPattern:@"count\\(.*\\)\\s*==\\s*0" inString:line])
        {
            ++warnings;
            Log(@"%@:%zd: warning: Line %zd: Consider replacing zero count check with isEmpty().", path, count, count);
        }
        
        // Test for any use of NSNotFound, use contains instead?
        if ([RegexHelper testPattern:@"!=\\s*NSNotFound" inString:line])
        {
            ++warnings;
            Log(@"%@:%zd: warning: Consider replacing NSNotFound pattern with contains()", path, count, count);
        }
        
        
        // Highlight enumeration prefixes for elimnation
        for (NSString *prefix in prefixes)
        {
            // Has enumeration prefix with dot after but no rawValue
            if ([line rangeOfString:[prefix stringByAppendingString:@"."]].location != NSNotFound &&
                [line rangeOfString:@"rawValue"].location == NSNotFound)
            {
                ++warnings;
                Log(@"%@:%zd: warning: Line %zd: Swift type inference may not require enumeration prefix on this line", path, count, count);
            }
        }
        
        // Find constructors, which in context may use inferrable class types
        if (_enableConstructors)
        {
            // Matches most no-arg class methods as likely constructors
            if ([RegexHelper testPatternCaseSensitive:@"^\\s*[:upper:]\\w+\\.\\w+\\(\\)" inString:line])
            {
                // first thing on line? skip.
            }
            else if ([RegexHelper testPatternCaseSensitive:@"let\\s*\\w+\\s*[=]\\s*[:upper:]\\w+\\.\\w+\\(\\)" inString:line] ||
                     [RegexHelper testPatternCaseSensitive:@"var\\s*\\w+\\s*[=]\\s*[:upper:]\\w+\\.\\w+\\(\\)" inString:line])
            {
                // after let or var assignment, skip. There won't be any context for type inference
            }
            else if ([RegexHelper testPatternCaseSensitive:@"[=]\\s*[:upper:]\\w+\\.\\w+\\(\\)" inString:line])
            {
                // after assignment, e.g. view.backgroundColor = UIColor.blueColor()
                ++cautions;
                Log(@"%@:%zd: note: Line %zd: CAUTION: Possible constructor assignment pattern may not require inferred prefix", path, count, count);
                Log(@"%@", line);
            }
            else if ([RegexHelper testPatternCaseSensitive:@"[ :,\{\(][:upper:]\\w+\\.\\w+\\(\\)" inString:line])
            {
                ++cautions;
                Log(@"%@:%zd: note: Line %zd: CAUTION: Possible constructor pattern may not require inferred prefix", path, count, count);
                Log(@"%@", line);
            }
        }
        
        // Self references
        BOOL treatSelfRefAsWarning = YES;
        if ([RegexHelper testString:@"self.init" inString:line])
        {
            // Skip self.init pattern
        }
        else if ([RegexHelper testPattern:@"self\\.(\\w+)\\s*=\\s*\\1" inString:line])
        {
            // Skip likely self-initialization self.x = x
        }
        else if ([RegexHelper testPattern:@"\\\\\\(self" inString:line])
        {
            // Skip likely in-string reference \(self
        }
        else if ([RegexHelper testPattern:@"\\{.*self" inString:line])
        {
            // Skip single line likely closure reference {....self...}
        }
        else if ([RegexHelper testPattern:@"self\\.(\\S)+\\s*=\\s*\\S" inString:line])
        {
            // initialization
            if (treatSelfRefAsWarning)
            {
                ++warnings;
                Log(@"%@:%zd: warning: Line %zd: Swift does not usually require 'self' references for assignments", path, count, count);
            }
            else
            {
                ++cautions;
                Log(@"%@:%zd: note: Line %zd: CAUTION: Swift does not usually require 'self' references for assignments", path, count, count);
                Log(@"%@", line);
            }
        }
        else if ([RegexHelper testString:@"self." inString:line])
        {
            // any other self refs
            if (treatSelfRefAsWarning)
            {
                ++warnings;
                Log(@"%@:%zd: warning: Line %zd: Swift does not usually require 'self' references outside of closures", path, count, count);
            }
            else
            {
                ++cautions;
                Log(@"%@:%zd: note: Line %zd: CAUTION: Swift does not usually require 'self' references outside of closures", path, count, count);
                Log(@"%@", line);
            }
        }
    }
    
    if (!_skipHygieneChecks)
    {
        // File-level line hygiene
        if ([string hasSuffix:@"\n\n"] || ![string hasSuffix:@"\n"])
        {
            ++warnings;
            Log(@"%@:0: warning: File %@ should have a single trailing newline", path, path.lastPathComponent);
        }
    }

    Log(@"%zd warnings, %zd cautions for %@", warnings, cautions, path.lastPathComponent);
}
@end

