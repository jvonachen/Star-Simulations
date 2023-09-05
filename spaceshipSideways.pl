#!/usr/bin/perl
use strict;
use warnings FATAL => "all";
use Time::HiRes;

print "Spaceship Sideways\nMaking pov files\n";

my $framesPerSecond = 24;
my $movieLengthSec = 600; # 10 minutes
my $totalFrames = $framesPerSecond * $movieLengthSec;
my $digits = length($totalFrames); # This is used in part of the ffmpeg command
my $startTime = [Time::HiRes::gettimeofday()]; # How long do various parts of the process take?

sub oneStar {
    my ($x, $y, $z, $brightness) = @_;
    return "
        // star
        sphere {
            <$x, $y, $z>, 1 // radius
            pigment { rgb<$brightness, $brightness, $brightness> }
            finish { ambient 1 }
        }
    ";
}

sub dist {
    my ($x1, $y1, $z1, $x2, $y2, $z2) = @_;
    return sqrt(($x2 - $x1) ** 2 + ($y2 - $y1) ** 2 + ($z2 - $z1) ** 2); 
}

# create a giant list of stars 
my $diameter = 1000; # The width and height of the square tube of stars
my $radius = $diameter / 2;
my $tubeLength = 100000;
my $numberOfStars = 100000;
my @stars;
while(scalar @stars < $numberOfStars) {
    sub rc { # random coordinate
        my ($size) = @_;
        return rand($size) - $size / 2;
    }

    # These are stars in a square tube with the origin in the center of the tube
    my $x = rc($diameter);
    my $y = rc($diameter);
    my $z = rc($tubeLength);
    
    # include only stars inside the cylinder
    if(dist(0, 0, $z, $x, $y, $z) < $radius) {
        push @stars, {x => $x, y => $y, z => $z};
    }
}

# Now generate pov ray sdl files and save them in a directory called staging.  Also keep track of the file names as a parameter file for paralelle.
my $heavenlyBodies; # the string to be saved with all the stars in this frame
my $cameraZ; # The camera sits on the x axis and moves from a -z to a +z
my $tripLength = $tubeLength - $diameter; # the trip should always show stars
my $startingZ = -$tubeLength / 2 + $radius;
my $params = ''; # a file with parameters for parallel
for (my $frame = 0; $frame < $totalFrames; $frame++) {
    # admittedly this is a bad way of doing animations.  The right way is to have a time so far scalar and tie together events to that time instead of frames.  But this is just a quickie program.
    $cameraZ = $startingZ + $frame / $totalFrames * $tripLength;

    $heavenlyBodies = ''; # clear out from a previous iteration
    for my $star (@stars) {
        my $x = %$star{x};
        my $y = %$star{y};
        my $z = %$star{z};
        my $distance = dist(0, 0, $cameraZ, $x, $y, $z);
        # Add a hemisphericle range of stars in front of the camera.  Also vary the brightness of the star based on distance.
        #if($x > 0 && $distance < $radius) {
        if($distance < $radius) {
            $heavenlyBodies .= oneStar($x, $y, $z, 1 - ($distance / $radius));
        }
    }

    # This rotates the look at point for the camera
    my $radians = $frame / 100; # This also should be based on time and not frames
    my $lookatX = cos($radians);
    my $lookatZ = $cameraZ + sin($radians);
    my $povrayFileContent = "
        camera {
            right x * 2538 / 1080
            location <0, 0, $cameraZ>
            look_at  <$lookatX, 0, $lookatZ>
        }

        $heavenlyBodies
    ";
        
    my $pad = '0' x ($digits - length($frame));
    my $povrayFilename = "staging/frame" . $pad . $frame . ".pov";
    open(FH, ">", $povrayFilename) or die $!;
    print FH $povrayFileContent;
    close(FH);

    $params .= "$povrayFilename\n";
}
print "Took " . Time::HiRes::tv_interval($startTime) . " seconds to generate pov files\n";

# write a params file for gnu parallel
open(FH, ">", 'params.txt') or die $!;
print FH $params;
close(FH);

# Generate the images - This could take a long time like more than a couple of hours for the whole thing for me.
$startTime = [Time::HiRes::gettimeofday()];
print "making png files\n";
`parallel -a params.txt povray +Q11 -W2538 -H1080 +A -D {1} 2>&1`;
`rm staging/*.pov`;
`rm params.txt`;
print "Took " . Time::HiRes::tv_interval($startTime) . " seconds to render\n";

$startTime = [Time::HiRes::gettimeofday()];
print "Making movie...";
my $command = "ffmpeg -y -r $framesPerSecond -i staging/frame%0" . $digits . "d.png take.mp4 2>&1";
`$command`;
`rm staging/*.png`;
print "Took additionally " . Time::HiRes::tv_interval($startTime) . " seconds to make movie.\n";
