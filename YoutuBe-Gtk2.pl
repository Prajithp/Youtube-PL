#!/usr/bin/perl

package YouTube;

use strict;
use warnings;
our $VERSION = '0.1'; #Beta

use Carp ();
use URI ();
use LWP::UserAgent;

my $base_url     = 'http://www.youtube.com/get_video_info?video_id=';

sub new {
  my $class = shift;
  my %args = @_;
  $args{ua} = LWP::UserAgent->new(
    agent      => __PACKAGE__.'/'.$VERSION,
    parse_head => 0,
  ) unless exists $args{ua};
  bless \%args, $class;
}

sub ua {
  my ($self, $ua) = @_;
  return $self->{ua} unless $ua;
  Carp::croak "Usage: $self->ua(\$LWP_LIKE_OBJECT)" unless eval { $ua->isa('LWP::UserAgent') };
  $self->{ua} = $ua;
}

sub _get_args {
  my ($self, $content) = @_;
  my @info = split /&/, $content;
  for ( @info ) {
    my ($key, $value) = split /=/;
    $self->{info}->{$key} = $value;
  }
  return $self->{info};
}

sub _get_content {
  my ($self, $video_id) = @_;
  local $Carp::CarpLevel = $Carp::CarpLevel + 1;
  my $url = "$base_url$video_id";
  my $res = $self->ua->get($url);
  Carp::croak "GET $url failed. status: ", $res->status_line if $res->is_error;
  return $res->content;
}

sub _fetch_video_url_map {
  my ($self, $content) = @_;
  my $args = $self->_get_args($content);
  unless ($args->{fmt_list} and $args->{url_encoded_fmt_stream_map}) {
    Carp::croak 'failed to find video urls';
  }
  my $fmt_map     = _parse_fmt_map($args->{fmt_list});
  my $fmt_url_map = _parse_stream_map($args->{url_encoded_fmt_stream_map});
  my $video_url_map = +{
    map {
      $_->{fmt} => $_,
    } map +{
      fmt        => $_,
      resolution => $fmt_map->{$_},
      url        => $fmt_url_map->{$_},
      suffix     => _suffix($_),
    }, keys %$fmt_map
  };
    return $video_url_map;
}

sub _parse_fmt_map {
  my $param = shift;
  $param       = _url_decode($param);
  my $fmt_map = {};
  for my $stuff (split ',', $param) {
    my ($fmt, $resolution) = split '/', $stuff;
    $fmt_map->{$fmt} = $resolution;
  }
  return $fmt_map;
}

sub _parse_stream_map {
  my $param       = shift;
  $param       = _url_decode($param);
  my $fmt_url_map = {};
  for my $stuff (split ',', $param) {
    my $uri = URI->new;
    $uri->query($stuff);
#     print STDERR Data::Dumper::Dumper($uri);
    my $query = +{ $uri->query_form };
    my $sig = $query->{sig} || '';
    my $url = $query->{url};
    $fmt_url_map->{$query->{itag}} = $url.'&signature=' . $sig;
  }
  return $fmt_url_map;
}

sub _suffix {
  my $fmt = shift;
  return $fmt =~ /43|44|45/    ? 'webm'
         : $fmt =~ /18|22|37|38/ ? 'mp4'
         : $fmt =~ /13|17/       ? '3gp'
         :                         'flv';
}

sub _fetch_title {
  my ($self, $content) = @_;
  my $args = $self->_get_args($content);
  my ($title) = $args->{title};
  $title =~  s/\+/_/g;     
  return $title;
}

sub _get_video_id {
  my ($self,$url) = @_;
  $url =~ s|http://||;
  $url =~ s|https://||;
  $url =~ s|www\.||;
  $url =~ s|youtube\.com/watch\?v=||;
  return (split '&', $url)[0];
}

sub _fetch_thumbnail {
  my ($self,$id) = @_;
  my $img_tmp_file = '/tmp/' . $id . '.jpg';
  my $img_url = 'http://img.youtube.com/vi/' . $id . '/default.jpg';
  my $res = $self->ua->get("$img_url");
  open(OUT, ">:raw", "$img_tmp_file");
  binmode OUT;
  if ($res->is_success) {
    print OUT $res->decoded_content(charset => 'none');    
  }
  return $img_tmp_file;
}

sub _url_encode {
  my $string = shift;
  $string =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
  return $string;
}

sub _url_decode {
  my $string = shift;
  $string =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  return $string;
}

package main;

import YouTube;
use strict;
use warnings;
# use Data::Dumper;
use Glib qw/TRUE FALSE/;
use Gtk2 '-init';
use utf8;
use encoding 'UTF-8';
use MIME::Base64 qw( decode_base64 );
use POSIX;


my $font     = Gtk2::Pango::FontDescription->from_string("Sans 15");
my $fontMono = Gtk2::Pango::FontDescription->from_string("Andale Mono Bold 8");
my $red   = Gtk2::Gdk::Color->new (0x8888,0,0);

my $button_select_cb;
my $video_format_cb = 'mp4';

my $window = Gtk2::Window->new;
my $client = YouTube->new();
$window->set_title('YouTube Downloader');
$window->signal_connect (destroy => sub {&delete_event;});
# $window->set_default_size(100, 150);

my $main_box = Gtk2::VBox->new();
$main_box->set_border_width(2);
$window->add($main_box);

my $heading_row = Gtk2::HBox->new();
$heading_row->set( "border_width" => 1 );
$main_box->pack_start($heading_row, FALSE, FALSE, FALSE);

my $image_data = decode_base64(<DATA>);
my $loader = Gtk2::Gdk::PixbufLoader->new;
$loader->write ($image_data);
$loader->close;
my $pixbuf = $loader->get_pixbuf;
my $image = Gtk2::Image->new_from_pixbuf ($pixbuf);
$heading_row->pack_start($image, TRUE, TRUE, FALSE);

my $heading_label_row = Gtk2::HBox->new();
$main_box->pack_start($heading_label_row, FALSE, FALSE, FALSE);

my $heading = Gtk2::Label->new("Downloader");
$heading->modify_font($font);
$heading_label_row->pack_start($heading, TRUE, TRUE, FALSE);



my $separator = Gtk2::HSeparator->new;
$main_box->pack_start($separator, FALSE, TRUE, 15);

my $first_row = Gtk2::HBox->new();
$main_box->pack_start($first_row, FALSE, FALSE, 5);

my $entry_label = Gtk2::Label->new("Enter YouTube url");
$entry_label->modify_font($fontMono);
$first_row->pack_start($entry_label, TRUE, TRUE, 5);

my $download_box = Gtk2::Entry->new;
$download_box->set_activates_default (TRUE);
$download_box->set_size_request(350, 30);
$first_row->pack_start($download_box, TRUE, TRUE, 5);

my $download_button = Gtk2::Button->new_with_label("Fetch Video");
$download_button->signal_connect( clicked => sub{ &fetch_video_meta; });
$download_button->set_size_request(150, 30);
$first_row->pack_start($download_button, FALSE, FALSE, 5);

my $error_row = Gtk2::HBox->new();
$main_box->pack_start($error_row, FALSE, FALSE, 5);

my $show_url_error = Gtk2::Label->new("Eg: https://www.youtube.com/watch?v=maTVM3iPlXA");
$show_url_error->modify_font($fontMono);
$show_url_error->modify_fg('normal',$red);
$error_row->pack_start($show_url_error, TRUE, TRUE, 5);

my $separator2 = Gtk2::HSeparator->new;
$main_box->pack_start($separator2, TRUE, TRUE, FALSE);

my $format_row = Gtk2::HBox->new();
$main_box->pack_start($format_row, FALSE, FALSE, FALSE);

my $radio_label = Gtk2::Label->new("Select Video Format");
$radio_label->modify_font($fontMono);
$radio_label->set_alignment(0.0, 0.0);
$format_row->pack_start($radio_label, TRUE, TRUE, FALSE);

my $value;
my $mp4 = Gtk2::RadioButton->new(undef,"mp4");
my $mp4_sig_id = $mp4->signal_connect("toggled" => sub {&handle_video_type('mp4');}, "MP4");
$mp4->signal_handler_block ($mp4_sig_id);

$format_row->pack_start($mp4, TRUE, TRUE, 5);
$mp4->set_active(TRUE);

my @group = $mp4->get_group;
my $flv = Gtk2::RadioButton->new_with_label(@group,"FLV");
my $flv_sig_id = $flv->signal_connect("toggled" => sub {&handle_video_type('flv');}, "FLV");
$flv->signal_handler_block ($flv_sig_id);

my $gp = Gtk2::RadioButton->new_with_label(@group,"3GP");
my $gp_sig_id = $gp->signal_connect("toggled" => sub {&handle_video_type('3gp');}, "3GP");
$gp->signal_handler_block ($gp_sig_id);

$mp4->signal_connect("enter" => sub { $mp4->signal_handler_unblock($mp4_sig_id)});
$mp4->signal_connect("leave" => sub { $mp4->signal_handler_block($mp4_sig_id)});
$flv->signal_connect("enter" => sub { $flv->signal_handler_unblock($flv_sig_id)});
$flv->signal_connect("leave" => sub { $flv->signal_handler_block ($flv_sig_id)});
$gp->signal_connect("enter"  => sub { $gp->signal_handler_unblock($gp_sig_id)});
$gp->signal_connect("leave"  => sub { $gp->signal_handler_block($gp_sig_id)});

$format_row->pack_start($flv, TRUE, TRUE, 5);
$format_row->pack_start($gp, TRUE, TRUE, 5);


  
my $second_row = Gtk2::HBox->new();
$main_box->pack_start($second_row, FALSE, FALSE, FALSE);

my $save_label = Gtk2::Label->new("Save to          ");
$save_label->modify_font($fontMono);
$second_row->pack_start($save_label, TRUE, TRUE, 5);

my $save_box = Gtk2::Entry->new;
my $cur = `pwd`;
chomp($cur);
utf8::encode($cur);
$save_box->set_text($cur);
$save_box->set_activates_default (TRUE);
$save_box->set_size_request(350, 30);
$second_row->pack_start($save_box, TRUE, TRUE, 5);

my $choose_button = Gtk2::Button->new_from_stock("gtk-save");
$choose_button->set_size_request(150, 30);
$second_row->pack_start($choose_button, FALSE, FALSE, 5);

my $download_row = Gtk2::HBox->new();
$main_box->pack_start($download_row, FALSE, FALSE, FALSE);

my $download_me = Gtk2::Button->new_from_stock("Download Me");
$download_me->set_size_request(300, 30);
$download_row->pack_start($download_me, TRUE, FALSE, 5);


my $separator3 = Gtk2::HSeparator->new;
$main_box->pack_start($separator3, TRUE, TRUE, FALSE);

my $third_row = Gtk2::HBox->new();
$main_box->pack_start($third_row, FALSE, FALSE, FALSE);

my $progress_row = Gtk2::HBox->new();
$main_box->pack_start($progress_row, FALSE, FALSE, FALSE);

my $progress_label = Gtk2::Label->new("");
$progress_label->modify_font($fontMono);
$progress_row->pack_start($progress_label, TRUE, TRUE, 5);



my $progress_bar = Gtk2::ProgressBar->new();
my $fraction = 0.0;
$progress_bar->set_fraction($fraction);
$progress_bar->hide;
$third_row->pack_start( $progress_bar, TRUE, TRUE, 15 );

# my $separator3 = Gtk2::HSeparator->new;
# $main_box->pack_start($separator3, FALSE, TRUE, 15);

my $bottom_row = Gtk2::HBox->new();
$main_box->pack_start($bottom_row, FALSE, TRUE, 5);

my $quit_button = Gtk2::Button->new_from_stock('gtk-quit');
$bottom_row->pack_end($quit_button, FALSE, FALSE, 5);
$quit_button->signal_connect(clicked => sub {&delete_event();});

# # my $about_button = Gtk2::Button->new_from_stock('gtk-about');
# # $bottom_row->pack_end($about_button, FALSE, FALSE, 5);
# # 
# # $about_button->signal_connect(clicked => sub {&show_about();});

$window->show_all;
$progress_bar->hide;
$second_row->hide;
$format_row->hide;
$download_row->hide;
Gtk2->main;



sub fetch_video_meta {
  $error_row->hide;
  $second_row->hide;
  $format_row->hide;
  $download_row->hide;
  my $video_url = $download_box->get_text;
  if ($video_url !~ m/youtube\.com\/watch\?v=([^\&\?\/]+)/is) {
     $show_url_error->set_label("Not a valid URL format");
     $error_row->show_all;
     return 0;
  }
  my $video_id = $client->_get_video_id($video_url);
  my $content  = $client->_get_content($video_id);
  my $title    = $client->_fetch_title($content);
  my $video_url_map = $client->_fetch_video_url_map($content);
  my $sorted;
  my($url, $suffix, $resolution, $hash);
  foreach my $id (keys(%{$video_url_map})) {
    $hash  = {
      "resolution" => $video_url_map->{$id}->{resolution}, 
      "suffix" 	   => $video_url_map->{$id}->{suffix},
      "url"        => $video_url_map->{$id}->{url},
    };
    $sorted->{$video_url_map->{$id}->{suffix}} = $hash
  }
  $format_row->show_all;
  $choose_button->signal_connect( clicked => sub{ &_choose_dir("$title"); });
  $second_row->show_all;
  my $return_vars = {"video_map" => $sorted, "video_tittle" => $title};
  $download_me->signal_connect( clicked => sub{ &get_video($return_vars); });
  $download_row->show_all;
}

sub get_video {
  my $call_back = shift;
  my $video_format = $video_format_cb;
  my $file_name = $save_box->get_text . '/' . $call_back->{video_tittle} . '.' . $video_format;
  my $download_url = $call_back->{video_map}->{$video_format}->{url};  
  open( IN, '>', "$file_name" ) or die $!;
  my $expected_length;
  my $bytes_received = 0;
  my $fraction = 0;
  my $res = $client->ua->request(HTTP::Request->new(GET => $download_url),
      sub {
	my ( $chunk, $res ) = @_;
	$bytes_received += length($chunk);
	unless ( defined $expected_length ) {
            $expected_length = $res->content_length || 0;
        }
	$fraction = $bytes_received / $expected_length if $expected_length;
	$progress_bar->show;
        $progress_bar->set_fraction($fraction);
        my $text = sprintf('%.2d', $fraction * 100) . '%';
        $progress_bar->set_text($text);
        my $total_length;
        if ($bytes_received gt '1024') {
          $total_length = ceil($bytes_received / (1024 * 1024)) . "MB" . ' Of ' . ceil($expected_length / (1024 * 1024)) . "MB";
        } else {
          $total_length = $bytes_received . "KB" . ' Of ' . ceil($expected_length / (1024 * 1024)) . "MB";
        }
        $progress_label->set_label($total_length);
        Gtk2->main_iteration while Gtk2->events_pending;
        print IN $chunk;
      }
  );
  close IN;
  $progress_bar->set_text("Completed");
}

sub _choose_dir {
  my $file_name = shift;
  my $file_chooser = Gtk2::FileChooserDialog->new(
	    'Save Video',
	    undef,
	    'select-folder',
	    'gtk-cancel' => 'cancel',
	    'gtk-ok' => 'ok');
#   $file_chooser->set_current_name("$file_name");
  my $full_path;
  if ('ok' eq $file_chooser->run) {
    $full_path = $file_chooser->get_filename;    
  }
  $file_chooser->destroy;
  my $cur_dir = `pwd`;
  chomp($cur_dir);
  $full_path = $cur_dir if (not $full_path);
  $save_box->set_text($full_path);
  return;
}

sub handle_video_type {
  my $value = shift;
  $value = 'mp4' if not $value;
  $video_format_cb = $value;
}

sub delete_event {
  my $pid = "$$";
  kill(15, $pid);  # otherwise LWP::UserAgent won't kill
   Gtk2->main_quit;
   return FALSE;
}


sub show_about {
  my $text = "Test";
  my $dialog = Gtk2::MessageDialog->new_with_markup (undef,
	[qw/modal destroy-with-parent/],
	'info',
	'ok',
	sprintf "$text");								
  my $retval = $dialog->run;
  #destroy the dialog as it comes out of the 'run' loop	
  $dialog->destroy;
}
__DATA__
iVBORw0KGgoAAAANSUhEUgAAAJkAAABTCAYAAACML6VoAAAAIGNIUk0AAHolAACAgwAA+f8AAIDpAAB1MAAA6mAAADqYAAAXb5JfxUYAAASTSURBVDjL7dU/zqQ2GMfxOUHEETjBO559m1SRq9QcgX4b2nS+AU16l0kTcQT3aTiCi0QpopVcRNomighE5pX32QfD5IVhwL+Rvs34D+z4s34vXdddENoy/AgIyBCQIQRkCMgQkCEEZAjIEAIyBGQIyBACMgRkCMgQAjIEZAgBGQIyBGTrvMABPt3rqwyq+lRQ3WeYXF+3Ydwza/JuFXn3vO/yRUC2O6xmYyh7ZD3ADMj2BVafEBeHTQDZPsB0AsDG3COgAdmXwKqEgI21QPZYZC5BZEMlkD0GWJEosM1vsy3QGFIzMU8yc4sdkSnyw9s+8z96z2E7spd9GLSDIWuHMyPlzLyamSd2RNaQH14tXEd7z2Ebspd6FLLfX16uR0JWMXhKZp4lc+xlxw9zCyWF7I+Xl++OhCxnkOkFc+qdkXUpI/vzev14GGQeUUsAOTJeMsiKJ0Nm/CGH5WRNycw5JLJP1+sPR0NWMYhEMK4pwp2BiYWHIck6s/Jh74bMCfHj0ZDlDLIqGLdkrNkZmUwd2V+3W3MoZB5SQyCZCMBy4vxFnwzKgAzIQmQlxTT1PYNnwGWYeUP1hBU6XwVjktknxFKtjEwGaTJWkfElyJo+4b/LmT1pOpg/rin73NSaz7fbr0dEljEHK5kbrmWAuQlgY3plZGplZLHbSJLxOWQl+W5s6tnFxPyhrK/l1v394cNvh0PmoTXMLUQBVQSLnQE2ViaALIuAKZnnVpH54a3mzoSsJAfL3VB5cG4FM24mcNpEkCn/fcFgCdc6Zq3ua5hn1mdCls/cRhSKioxzALOTI6Nr88haTcZ0BKA8DTIPrY0gq2duIzpO18vEkMXWKjJmI2vzsyFTEWTyjj95WyIzJ0TW3bH28MjkBDDnx4EMyFaBxiHTQLYpMkMSZ0dmmEMunwiZPiGyuU6HTDGHnD0RMgVkJ0QWjAHZNsjkTEAGZO9G1t0TkAEZkAHZIZBpP0dx/14g2x5ZkQCy2Nru8+32C5Bti0yeEJm7B9k/r68/p4KsJvNMMCYYKCKCrA7G9JMgs33ZO5CJyFpNxhoyHj43Y975p1SQlQyGyt9ELfnezdyC1q9rmD0psmxDZMLfKsPcnIzNIcsDLDUZo+9smee2/tn0liuYd65SQZZ5PN2CNFmrFq77CpkHsxUyCiO/A1kW2Yu7fWVkfphJGdnF31xzQJwHuXRduwCZXRGZmADWMhBiyKqJvYY081wXmT+mJt75+5SQzd1Ktk8wa/KJW3DYSy5AZlZE1pBbSHpg3Z3IlIdTke/LyDs6P05x5f69ptZ9e3Rk0h/2WzPIRjTDXOPTfeUl/hF+3jC/9nuEe4VRZHoBsntyHk270n72zv3G5y9d882hkc0AfIqPvy26RHObnjGQvSETCSPTQPY4aCZRZBLIcJttWbP5GQPZV9DKhIC1fRmQ7QfNnRyYeQQwIItDy/vqE2Jr/X+iy38B2VOhkyRFavztEGY3gmKZZxnmnQryztkbrpSQofOHHwEBGQIyhIAMARkCMoSADAEZQkCGgAwBGUJAhoAMARlCQIaADCEgQw/pX0W3NRkK99BVAAAAAElFTkSuQmCC
