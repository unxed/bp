{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 2000 by Berczi Gabor

    Strings for utilities

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}

{ $undef USERESSTRINGS} { this doesn't compile under FP!!! why? }

{$ifdef USERESSTRINGS}
    resourcestring
{$else}
    const
{$endif}

    btn_OK = 'O~K~';
    btn_Cancel = 'Mégsem';

    dialog_find = 'Keresés';
    label_find_options = 'Opciók';
    label_find_texttofind = '~K~eresendő';
    label_find_casesensitive = 'K~i~s-/nagybetők külön';
    label_find_wholewordsonly = 'Csak teljes sza~v~akat';
    label_find_direction = 'Irány';
    label_find_forward = 'Előre (~d~)';
    label_find_backward = 'Visszafelé (~b~)';
    label_find_scope = 'Szkóp';
    label_find_global = 'Teljes szöve~g~';
    label_find_selectedtext = 'Kivála~s~ztott szöveg';
    label_find_origin = 'Kiindulási pont';
    label_find_fromcursor = 'A kur~z~ortól';
    label_find_entirescope = 'T~e~ljes szkóp';

    dialog_replace = 'Csere';
    label_replace_texttofind = label_find_texttofind;
    label_replace_newtext = '   ~Ú~j szöveg';
    label_replace_options = label_find_options;
    label_replace_casesensitive = label_find_casesensitive;
    label_replace_wholewordsonly = label_find_wholewordsonly;
    label_replace_promptonreplace = '~P~rompt on replace';
    label_replace_direction = label_find_direction;
    label_replace_forward = label_find_forward;
    label_replace_backward = label_find_backward;
    label_replace_scope = label_find_scope;
    label_replace_global = label_find_global;
    label_replace_selectedtext = label_find_selectedtext;
    label_replace_origin = label_find_origin;
    label_replace_fromcursor = label_find_fromcursor;
    label_replace_entirescope = label_find_entirescope;
    btn_replace_changeall = '~A~z összeset';

    dialog_gotoline = 'Ugrás sorra';
    label_gotoline_linenumber = 'Az új sor s~z~áma';

    msg_invalidmarkindex = 'Érvénytelen pont index (%d)';
    msg_marknotset = 'A %d. pont nincs beállítva.';

    msg_foldboundsarenotvalid = 'A hajtás határai nem érvényesek';

    msg_notenoughmemoryforthisoperation = 'Nincs elég memória a mővelet elvégzéséhez.';
    msg_errorreadingfile = 'Hiba a  %s fájl olvasása közben.';
    msg_errorwritingfile = 'Hiba a  %s fájl írása közben.';
    msg_errorsavingfile = 'Hiba a %s fájl mentése közben.';
    msg_errorcreatingfile = 'Hiba a %s fájl létrehozása közben.';
    msg_filehasbeenmodifiedsave = 'A %s módosult. Menti?';
    msg_saveuntitledfile = 'Elmenti a cím nélküli fájlt?';
    msg_filehadtoolonglines = #3'A %s fájlnak túl hosszú'#13+
                              #3'sora(i) voltak. Az első a %d';
    msg_filewasmodified = #3'A %s fájlt'#13+
                          #3'egy másik program módosította.'#13+
                          #3'Felülírja az újabb verziót?';

    dialog_savefileas = 'Fájl mentése más néven';
    dialog_writeblocktofile = 'Blokk kiírása fájlba';
    dialog_readblockfromfile = 'Blokk beolvasása fájlból';

    label_name = '~N~év';

    msg_searchstringnotfound = 'A keresett karaktersor nem található.';
    msg_replacethisoccourence = 'Lecseréljem ezt az előfordulást?';
    msg_fileexistsoverwrite = 'A %s fájl már létezik. Felülírja?';

    { Help system }

    msg_nohelpfilesinstalled = 'Nincsenek súgó-fájlok telepítve.';
    msg_helpindex = 'Súgó index';
    msg_nohelpavailabelforthistopic = 'Ehhez a témához nem tartozik súgó.';
    msg_pagenotavailable = 'Az oldal nem elérhető';
    msg_cantaccessurl = 'Sajnos nem tudom megnyitni a %s URL-t...';

    { WUtils }
    msg_bugcheckfailed = 'Belső hiba: %s'#13+
                         'Kérem, jelezze a szerzőnek!';
    msg_functionnotimplemented = #3'Ez a funkció még'#13+
                                 #3+'nincs kidolgozva...'#13+
                                 #3+'';

