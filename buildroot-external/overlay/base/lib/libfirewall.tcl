#!/bin/tclsh

##
# @file  setfirewall.tcl
# @brief Firewall-Konfiguration
##

##
# @const Firewall_CONFIG_FILE
# Konfigurationsdatei f�r die Firewall
##
set Firewall_CONFIG_FILE /etc/config/firewall.conf

##
# @const Firewall_SERVICES
# Enth�lt die verf�gbaren Services und deren TCP-Ports
#
# Jeder Service kann als assoziatives Array mit den folgenden
# Elementen aufgefasst werden:
#   PORTS : Liste der TCP-Portnummern des Services
#   ACCESS: Zugriffsrechte f�r den Service:
#           full      : Vollzugriff; keine Einschr�nkungen
#           restricted: Eingeschr�nkter Zugriff
#           none      : Kein Zugriff m�glich
##
array set Firewall_SERVICES {}
set Firewall_SERVICES(XMLRPC) [list PORTS [list 2000 2001 2002 2010 9292] ACCESS full]
set Firewall_SERVICES(REGA)   [list PORTS [list 8181] ACCESS restricted]

##
# @var Firewall_IPS
# IP-Adressen f�r den eingeschr�nkten Zugriff
#
# Beinhaltet eine Liste der IP-Adressen oder Addressgruppen, denen bei
# eingeschr�nktem Zugriff eine Verwendung des jeweiligen Serices noch erlaubt
# ist.
##
set Firewall_IPS [list 192.168.0.1 192.168.0.0/16 fc00::/7]

##
# @fn loadConfiguration
# L�dt die Firwall-Einstellunfen aus der Konfigurationsdatei
##
proc Firewall_loadConfiguration { } {
  global Firewall_CONFIG_FILE Firewall_SERVICES Firewall_IPS
  
  array set config  {}
  array set section {}
  set sectionName   {}
  
  if { ![catch { set fd [open $Firewall_CONFIG_FILE r] }] } then {
    catch {
      while { ![eof $fd] } {

        set line [string trimleft [gets $fd]]

        if { "\#" != [string index $line 0] } then {

          if { [regexp {\[([^\]]+)\]} $line dummy newSectionName] } then {
          set config($sectionName) [array get section]
            array_clear section
            set sectionName $newSectionName
          }
  
          if { [regexp {([^=]+)=(.+)} $line dummy name value] } then {
            set section([string trim $name]) [string trim $value]
          }

        }      
    
      }
      set config($sectionName) [array get section]
      array_clear section
    }
  
    close $fd
  }
  
  foreach sectionName [array names config] {

    if { {} != $sectionName } then {
      array set section $config($sectionName)
      set ports  [array_getValue section Ports]
      set id     [array_getValue section Id]

      # Check if port 2010 for the service XMLRPC is set - if not add it.
      if {$sectionName == "SERVICE XMLRPC"} {
       if {[string first 2010 $ports] == -1} {
           append ports " 2010"
         }
       }

      set access [array_getValue section Access]
      
      set Firewall_SERVICES($id) [list PORTS [lsort -integer $ports] ACCESS $access]
      
      array_clear section
    }
  }

  if { [info exists config()] } then {
    array set emptySection $config()
    set Firewall_IPS [array_getValue emptySection IPs]
  }
  
}

##
# @fn saveConfiguration
# Speichert die Firewall-Einstellungen in der Konfigurationsdatei
##
proc Firewall_saveConfiguration {} {
  global Firewall_CONFIG_FILE Firewall_SERVICES Firewall_IPS
  
  set fd [open $Firewall_CONFIG_FILE w]
  catch {
  
    puts $fd "# Firewall Configuration file"
    puts $fd "#   created [clock format [clock seconds]]"
    puts $fd "# This file was automatically gernerated"
    puts $fd "# Please do not change anything"
    puts $fd ""
    
    puts $fd "IPs = $Firewall_IPS"
    puts $fd ""
    
    foreach serviceName [array names Firewall_SERVICES] {
      array set service $Firewall_SERVICES($serviceName)
      puts $fd "\[SERVICE $serviceName\]"
      puts $fd "Id = $serviceName"
      puts $fd "Ports = $service(PORTS)"
      puts $fd "Access = $service(ACCESS)"
      puts $fd ""
    }
    
  }
    close $fd
}

##
# @fn configureFirewall
# Konfiguriert die Firewall
##
proc Firewall_configureFirewall { } {
  global Firewall_SERVICES Firewall_IPS
  
  exec_cmd "/usr/sbin/iptables -F"
  exec_cmd "/usr/sbin/iptables -P INPUT ACCEPT"
  exec_cmd "/usr/sbin/iptables -A INPUT -i lo -j ACCEPT"
  exec_cmd "/usr/sbin/iptables -A INPUT -p tcp --dport 8182 -j DROP"
  exec_cmd "/usr/sbin/iptables -A INPUT -p tcp --dport 8183 -j DROP"

  exec_cmd "/usr/sbin/ip6tables -F"
  exec_cmd "/usr/sbin/ip6tables -P INPUT ACCEPT"
  exec_cmd "/usr/sbin/ip6tables -A INPUT -i lo -j ACCEPT"
  exec_cmd "/usr/sbin/ip6tables -A INPUT -p tcp --dport 8182 -j DROP"
  exec_cmd "/usr/sbin/ip6tables -A INPUT -p tcp --dport 8183 -j DROP"

  foreach serviceName [array names Firewall_SERVICES] {
    array set service $Firewall_SERVICES($serviceName)
  
    if { $service(ACCESS) == "restricted" } then {
      foreach port $service(PORTS) {
        foreach ip $Firewall_IPS {
          if { [regexp {:} $ip] } then {
            exec_cmd "/usr/sbin/ip6tables -A INPUT -p tcp --dport $port -s $ip -j ACCEPT"
          } else {
            exec_cmd "/usr/sbin/iptables -A INPUT -p tcp --dport $port -s $ip -j ACCEPT"
          }
        }
      }
    }
    
    if { $service(ACCESS) == "none" || $service(ACCESS) == "restricted"} then {
      foreach port $service(PORTS) {
        exec_cmd "/usr/sbin/iptables -A INPUT -p tcp --dport $port -j DROP"
        exec_cmd "/usr/sbin/ip6tables -A INPUT -p tcp --dport $port -j DROP"
      }
    }
  
  }
  
}

##
# @fn exec_cmd
# F�hrt eine Kommandozeile aus
##
proc exec_cmd {cmdline} {
  set fd [open "|$cmdline" r]
  close $fd
}

##
# @fn array_clear
# L�scht die Elemente in einem Array
##
proc array_clear {name} {
  upvar $name arr
  foreach key [array names arr] {
    unset arr($key)
  }
}

##
# @fn array_getValue
# Liefert einen Wert aus einem Array
# Ist der Wert nicht vorhanden, wird {} zur�ckgegeben
##
proc array_getValue { pArray name } {
  upvar $pArray arr

  set value {}
  catch { set value $arr($name) }

  return $value
}
