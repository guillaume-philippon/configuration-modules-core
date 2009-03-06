# ${license-info}
# ${developer-info}
# ${author-info}


package NCM::Component::nfs;

use strict;
use NCM::Component;
use vars qw(@ISA $EC);
@ISA = qw(NCM::Component);
$EC=LC::Exception::Context->new->will_store_all;
use NCM::Check;
use File::Copy;

use EDG::WP4::CCM::Element;

use File::Path;


local(*DTA);


##########################################################################
sub Configure($$@) {
##########################################################################
    
  my ($self, $config) = @_;

  # The absolute names of configuration files. 
  my $exports = "/etc/exports";
  my $fstab = "/etc/fstab";

  # Path names.
  my $base = "/software/components/nfs";

  # Load ncm-nfs configuration into a hash
  my$nfs_config = $config->getElement($base)->getTree();
  
  # Collect information for exports file.
  my $contents .= "#\n# File generated by ncm-nfs on " . 
                  localtime() . ".\n#\n";


  #########################################
  # Process exports to build /etc/exports #
  #########################################
      
  if ($nfs_config->{'exports'}) {
  
    # Pull out the parameters from the configuration. 
    my $exports = $nfs_config->{'exports'};
    
    # Loop through all of the servers creating a line for each.
    for my $entry (@{$exports}) {}
      my $path = $entry->{'path'};
      my $hosts = $entry->{'hosts'};
      
      my @entries;
      for my $host_e (keys(%{$hosts}) ) {
        my $host = unescape($host_e);
        push @entries, "$host($hosts->{$host_e})";
      }
  
      # Only actually write the line if there was at least one 
      # valid host/option entry. 
      if (@entries) {
        $contents = "$path ".join(',',@entries)."\n";
      }
    }
  }

  # Now just create the new configuration file.  Be careful to save
  # a backup of the previous file if necessary.
  my $result = LC::Check::file($exports,
                               backup => ".old",
                               contents => $contents,
                              );
  $self->log("$exports created/updated") if $result;


  ##############################################
  # Process mount points and update /etc/fstab #
  ##############################################
      
  # Collect information for fstab file.
  $contents = "# File generated by ncm-nfs on " . 
         localtime() . ".\n";
  $contents .= "# Only nfs file systems managed by ncm-nfs component.\n";

  # Extract fstab information from existing file.
  my %oldnfs;
  my @oldnfs_order = ();
  open FSTAB, "<$fstab";
  while (<FSTAB>) {
    if (m/^\s*$/ or m/^\s*\#/) {
      # Keep blank lines or comments in the output file, although
      # leave out anything with the component name in it to avoid
      # ever growing file.
      if (! m/^\s*\#.*ncm-nfs.*/) {
        $contents .= $_;
      }
    } else {
      my ($device,$mntpt,$fstype,$opt,$freq,$passno) = split;
      $opt = "defaults" unless $opt;
      $freq = 0 unless defined($freq);
      $passno = 0 unless defined($passno);
      
      if ($fstype =~ /^nfs/) {
        # It is an nfs entry, save the information.
        $oldnfs{$device} = {"device" => $device,
                            "mntpt" => $mntpt,
                            "fstype" => $fstype,
                            "opt" => $opt,
                            "freq" => $freq,
                            "passno" => $passno};
        push(@oldnfs_order,$device);
      } else {
        # If the fstype doesn't begin with nfs (i.e. nfs or nfs4),
        # then just add the line to the output. 
        $contents .= $_;
      }
    }
  }
  close FSTAB;

  # Now check the information given in the configuration.  Make sure
  # that the configuration is preserved.
  my %newnfs;
  my @newnfs_order = ();

  if ( $nfs_config->{'mounts'} ) {
    my $mounts = $nfs_config->{'mounts'};
    
    # Loop through all of the servers creating a line for each.
    for my $mount (@{$mounts}) {
      my $device = $mount->{'device'};
      my $mntpoint = $mount->{'mountpoint'};
      my $fstype = $mount->{'fstype'};
      my $options;
      if ( $mount->{'options'} ) {
        $options = $mount->{'options'};
      } else {
        $options = "defaults";
      }
      my $freq;
      if ( $mount->{'freq'} ) {
        $freq = $mount->{'freq'};
      } else {
        $freq = 0;
      }
  
      my $passno;
      if ( $mount->{'passno'} ) {
        $passno = $mount->{'passno'};
      } else {
        $passno = 0;
      }
  
      #store the device order
      push(@newnfs_order,$device);
  
      # Add the entry. 
      $newnfs{$device} = {"device" => $device,
                          "mntpt" => $mntpoint,
                          "fstype" => $fstype,
                          "opt" => $options,
                          "freq" => $freq,
                          "passno" => $passno,
                          "action" => 0
                         };
    }
  }
  
  # Add to the configuration file the new NFS locations.  Creating
  # the new mount points as necessary.  At the same time determine
  # what action will need to be taken (none, mount, unmount/mount, 
  # or remount). 
  foreach ( @newnfs_order ) {
    # Extract the entry from the hash.
    my $hashref = $newnfs{$_};
    my %hash = %$hashref;
  
    $contents .= 
        $hash{device} . ' ' . 
        $hash{mntpt} . ' ' . 
        $hash{fstype} . ' ' . 
        $hash{opt} . ' ' . 
        $hash{freq} . ' ' . 
        $hash{passno} . "\n";
  
    # If the directory doesn't exist, then create it.  Issue a
    # warning if this couldn't be done. 
    my $mntpt = $hash{mntpt};
    mkpath($mntpt,0,0755) unless (-e $mntpt);
    unless (-d $mntpt) {
      $self->warn("error creating mountpoint $mntpt");
    }
  
    # Check matching entry in oldnfs.
    if (! defined($oldnfs{$_})) {
      $hashref->{action} = 'mount';
    } else {
      my $flag = compare_entries($hashref, $oldnfs{$_});
      if ($flag == 0) {
        $hashref->{action} = 'none';
      } elsif ($flag == 1) {
        $hashref->{action} = 'umount/mount';
      } else {
        $hashref->{action} = 'remount';
      }
    }
  }

  # Now just create the new configuration file.  Be careful to save
  # a backup of the previous file if necessary.
  $result = LC::Check::file($fstab,
                            backup => ".old",
                            contents => $contents,
                           );
  $self->log("$fstab created/updated") if $result;
  
  # Unmount the file systems which are going away.   Do the unmounting
  # in the reverse order that the file systems are defined.
  foreach ( reverse @oldnfs_order ) {
    my $hashref = $oldnfs{$_};
    my $mntpt = $hashref->{mntpt};
    
    my $nref = $newnfs{$_};
    
    # Unmount volume ONLY if new entry doesn't exist or the 
    # mount point has changed.
    if (!defined($nref) || ($nref->{action} eq 'umount/mount') ) {
      $self->log("Unmounting $mntpt\n");
      system("umount -l $mntpt");
      if ($?) {
        $self->warn("Error unmounting $mntpt\n");
      } else {
        # Try removing mount point, giving warning on error.
        unless (rmdir $mntpt) {
          $self->warn("can't delete mountpoint $mntpt");
        }
      }
    }
  }

  # Mount, unmount/mount, or remount as appropriate.
  foreach ( @newnfs_order ) {
    # Entry from the current configuration.
    my $hashref = $newnfs{$_};
  
    # Extract the mountpoint and the action.
    my $mntpt = $hashref->{mntpt};
    my $action = $hashref->{action};
  
    # Perform the necessary action.
    if (($action eq 'mount') || ($action eq 'umount/mount')) {
        $self->log("Mounting $mntpt\n");
        system("mount $mntpt");
        $self->warn("Error mounting $mntpt\n") if ($?);
    } elsif ($action eq 'remount') {
        $self->log("Remounting $mntpt\n");
        system("mount -o remount $mntpt");
        $self->warn("Error remounting $mntpt\n") if ($?);
    } else {
        $self->log("No action needed for $mntpt\n");
    }
  }

  # Force a reload of the nfs daemon. 
  $self->log("Forcing nfs reload\n");
  system("service nfs reload");
  if ($?) {
    $self->warn("Error on nfs reload\n");
  }

  return 1;
}

# Compares two NFS entries for equality.  If equal, then
# 0 is returned.  If the entries differ in the devices or
# mountpoint, then 1 is returned.  Otherwise, 2 is returned.
sub compare_entries($$) {

    my ($nref, $oref) = @_;

    return 1 if ($nref->{device} ne $oref->{device});
    return 1 if ($nref->{mntpt} ne $oref->{mntpt});
    return 2 if ($nref->{fstype} ne $oref->{fstype});
    return 2 if ($nref->{opt} ne $oref->{opt});
    return 2 if ($nref->{freq} != $oref->{freq});
    return 2 if ($nref->{passno} != $oref->{passno});

    # Got the end, so hashes must be equal.
    return 0;
}


1;      # Required for PERL modules
