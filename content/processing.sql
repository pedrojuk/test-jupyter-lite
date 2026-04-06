DELETE
FROM address_input;


INSERT INTO address_input (electorKey, PostCode, address1, address2, address3, address4, address5)
SELECT addressKey,
       PostCode,
       address1_1,
       address2_1,
       address3_1,
       address4_1,
       address5_1
FROM <LOCAL addresses>;

/*
-- populate the towns table - candidates - refine by hand, only do once

DELETE FROM towns;

INSERT INTO towns (town)
SELECT
 address3 entity
FROM address_input
WHERE address3 <> ''
GROUP BY entity
HAVING count(*) > 5
ORDER BY count(*) DESC;

INSERT INTO towns (town)
SELECT
 address2 entity
FROM address_input
WHERE address2 <> ''
AND address2 NOT IN (SELECT town FROM towns)
GROUP BY entity
HAVING count(*) > 300
ORDER BY count(*) DESC;
*/ -- stage 0 - apply any manual corrections in addressCorrection to raw addresses
-- PJ 20260202 added postcode

DROP TABLE IF EXISTS tempaddr0;


CREATE TEMP TABLE tempaddr0 AS
SELECT r.electorKey,
       COALESCE(c.postcode, r.postcode) AS postcode,
       COALESCE(c.address1, r.address1) AS address1,
       COALESCE(c.address2, r.address2) AS address2,
       COALESCE(c.address3, r.address3) AS address3,
       COALESCE(c.address4, r.address4) AS address4,
       r.address5,
       r.address6
FROM address_input r
LEFT OUTER JOIN addressCorrections c ON c.electorKey = r.electorKey;

-- stage 1 - tidy and concatenate addresses
-- concatenates addresses, replaces commas with | and removes unwanted spaces and doubled separators

DROP TABLE IF EXISTS tempaddr1;


CREATE TEMP TABLE tempaddr1 AS
SELECT electorKey,
       postcode,
       REPLACE(REPLACE(REPLACE(concat(trim(address1), iif(trim(address2) <> "", concat("|", trim(address2)), ""), iif(trim(address3) <> "", concat("|", trim(address3)), ""), iif(trim(address4) <> "", concat("|", trim(address4)), ""), iif(trim(address5) <> "", concat("|", trim(address5)), "")), ",", "|"), "| ", "|"), "||", "|") concatAddr
FROM tempaddr0;

-- stage 2 - remove town elements
-- just keep the bit of the address before London (or whatever town)
-- PJ 20260106 added fix for the addresses that don't contain London (now any town)
-- PJ 20260123 generalised for any row in table towns, not just London. Also handles Mitcham
-- PJ 20260123 FIXED matches town name wherever it occurs - needs to be at the end of the address
-- PJ 20260203 properly fixed this by looking for last separator

DROP TABLE IF EXISTS tempaddr2;


CREATE TEMP TABLE tempaddr2 AS
SELECT DISTINCT electorKey,
                postcode,
                concatAddr,
                instr(concatAddr||'$', REPLACE(concatAddr, rtrim(concatAddr, REPLACE(concatAddr, "|", "")), "")||'$') townStartPos,
                substr(concatAddr, instr(concatAddr||'$', REPLACE(concatAddr, rtrim(concatAddr, REPLACE(concatAddr, "|", "")), "")||'$')) townmatch, --town,
 iif(town IS NULL, concatAddr, substr(concatAddr, 1, instr(concatAddr||'$', REPLACE(concatAddr, rtrim(concatAddr, REPLACE(concatAddr, "|", "")), "")||'$')-2)) noLondon
FROM tempaddr1 t
LEFT OUTER JOIN towns --ON instr(concatAddr, "|"||town) > 0;
--ON instr(concatAddr, "|"||town) = (length(concatAddr)-length(town));
ON substr(concatAddr, instr(concatAddr||'$', REPLACE(concatAddr, rtrim(concatAddr, REPLACE(concatAddr, "|", "")), "")||'$')) = town;

-- stage 2a - repeat stage 2 to remove suburb

DROP TABLE IF EXISTS tempaddr2a;


CREATE TEMP TABLE tempaddr2a AS
SELECT DISTINCT electorKey,
                postcode,
                noLondon nL1,
                instr(noLondon||'$', REPLACE(noLondon, rtrim(noLondon, REPLACE(noLondon, "|", "")), "")||'$') townStartPos,
                substr(noLondon, instr(noLondon||'$', REPLACE(noLondon, rtrim(noLondon, REPLACE(noLondon, "|", "")), "")||'$')) townmatch, --town,
 iif(town IS NULL, noLondon, substr(noLondon, 1, instr(noLondon||'$', REPLACE(noLondon, rtrim(noLondon, REPLACE(noLondon, "|", "")), "")||'$')-2)) noLondon
FROM tempaddr2 t2
LEFT OUTER JOIN towns t --ON instr(noLondon, "|"||town) > 0;
--ON instr(noLondon, "|"||town) = (length(noLondon)-length(town));
ON substr(noLondon, instr(noLondon||'$', REPLACE(noLondon, rtrim(noLondon, REPLACE(noLondon, "|", "")), "")||'$')) = town;

-- stage 2b - repeat stage 2a to remove 2nd level suburb

DROP TABLE IF EXISTS tempaddr2b;


CREATE TEMP TABLE tempaddr2b AS
SELECT DISTINCT electorKey,
                postcode,
                noLondon nL2,
                instr(noLondon||'$', REPLACE(noLondon, rtrim(noLondon, REPLACE(noLondon, "|", "")), "")||'$') townStartPos,
                substr(noLondon, instr(noLondon||'$', REPLACE(noLondon, rtrim(noLondon, REPLACE(noLondon, "|", "")), "")||'$')) townmatch, --town,
 iif(town IS NULL, noLondon, substr(noLondon, 1, instr(noLondon||'$', REPLACE(noLondon, rtrim(noLondon, REPLACE(noLondon, "|", "")), "")||'$')-2)) noLondon
FROM tempaddr2a t2
LEFT OUTER JOIN towns t --ON instr(noLondon, "|"||town) > 0;
--ON instr(noLondon, "|"||town) = (length(noLondon)-length(town));
ON substr(noLondon, instr(noLondon||'$', REPLACE(noLondon, rtrim(noLondon, REPLACE(noLondon, "|", "")), "")||'$')) = town;

-- stage 3 - add position of last ! separator
--

DROP TABLE IF EXISTS tempaddr3;


CREATE TEMP TABLE tempaddr3 AS
SELECT electorKey,
       postcode,
       noLondon, -- handy use of rtrim to get everything to the right of the last separator
 -- since SQLite has no reverse instr function.
 -- https://stackoverflow.com/questions/21388820/how-to-get-the-last-index-of-a-substring-in-sqlite
 -- PJ 20260123 tweakd so it isn't tripped up by 40 Brixton Hill Court|40 Brixton Hill
 -- PJ 20260205 fixed incorrect match, which is a better solution to the Brixton Hill Court problem too.
 iif(instr(noLondon, '|') = 0, 0, LENGTH(rtrim(noLondon, replace(noLondon, "|", "")))) lastSepPos
FROM tempaddr2b;

-- stage 4 - split first and second parts
-- first part contains block number etc, where present
-- remainder is the street address
-- FIXME: sometimes street address gets split by this if house number is in a different column from street
--        e.g. 5A|Babington Road.
--        In this case the 5A should end up as part of the street address
--        How to detect. There is no block and no number in street.

DROP TABLE IF EXISTS tempaddr4;


CREATE TEMP TABLE tempaddr4 AS
SELECT electorKey,
       postcode,
       iif(lastSepPos > 0, substr(noLondon, 1, lastSepPos -1), "") firstPart,
       iif(lastSepPos > 0, substr(noLondon, lastSepPos + 1, 99), noLondon) streetAddress
FROM tempaddr3;

-- stage 4.5 find the position of the last space, so we can extract the last word

DROP TABLE IF EXISTS tempaddr4_5;


CREATE TEMP TABLE tempaddr4_5 AS
SELECT electorkey,
       firstPart,
       instr(firstPart, REPLACE(firstPart, rtrim(firstPart, REPLACE(firstPart, " ", "")), ""))-1 lastSpacePos
FROM tempaddr4;


DROP TABLE IF EXISTS tempaddr4_6;


CREATE TEMP TABLE tempaddr4_6 AS
SELECT electorKey,
       firstPart,
       iif(lastSpacePos > 0, substr(firstPart, lastSpacePos + 1, 99), "") AS lastWord,
       lastSpacePos
FROM tempaddr4_5;

-- stage 5 extract the ones with blocks. It's in a block if one of the block signifiers
-- is the last word of firstPart

DROP TABLE IF EXISTS tempaddr5;


CREATE TEMP TABLE tempaddr5 AS
SELECT electorKey,
       firstPart,
       b.blockSig,
       lastSpacePos + 1 AS blockPos
FROM tempaddr4_6 t
INNER JOIN blockSigs b ON b.blockSig = t.lastWord;

-- stage 5a - repeat but matching the candidate blocks or sub-streets from the candidateBlocks table
--            created by looking for repeated subaddresses in a previous run

INSERT INTO tempaddr5 (electorKey, firstPart, blockSig, blockPos)
SELECT electorKey,
       firstPart,
       a1 AS blockSig,
       INSTR(firstPart, cb.a1) AS blockPos
FROM tempaddr4_6
INNER JOIN candidateBlocks cb ON INSTR(firstPart, cb.a1) > 0
WHERE lastword NOT IN
    (SELECT blocksig
     FROM blockSigs bs)
  AND lastword <> '';

-- stage 6: process the block part to isolate the number within block and the block name
-- strips any "Flat" or "Apartment" from the front
-- PJ 20251210 added unit, studio and room

DROP TABLE IF EXISTS tempaddr6;


CREATE TEMP TABLE tempaddr6 AS WITH flatSeps(flatSep) AS (
                                                          VALUES ('Flat'), ('Apartment'), ('Unit'), ('Room'), ('Studio'))
SELECT electorKey,
       REPLACE(firstPart, "|", " ") firstPart,
       iif(f.flatSep IS NULL, REPLACE(firstPart, "|", " "), substr(REPLACE(firstPart, "|", " "), LENGTH(f.flatSep) + 2, 99)) rawBlockAddr,
       f.flatSep
FROM tempaddr5 t
LEFT OUTER JOIN flatSeps f ON instr(firstpart, f.flatSep) = 1;

-- stage 7 - extract the block name and generate sortable address in block
-- PJ 20251210 changed to use algorithm created for address file processing - more precise:
--     - doesn't strip where unnecessary
--     - copes with all kinds of number and letter flat formats

DROP TABLE IF EXISTS tempaddr7;


CREATE TEMP TABLE tempaddr7 AS
SELECT electorKey,
       firstPart,
       rawBlockAddr,
       flatSep, -- strip up until first space to get block name
 -- substr(rawBlockAddr, instr(rawBlockAddr," ") + 1, 99) blockName, <-- superseded by better method
 -- if the first "word" has any numbers in it or is 1 character long, it's assumed to be a flat number and the rest is a block name. If not, the whole thing is a block name
 iif((instr(rawBlockAddr, ' ') - 1) <> LENGTH(ltrim(rtrim(substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ') - 1), '1234567890'), '123456789'))
     OR instr(rawBlockAddr, ' ') = 2, substr(rawBlockAddr, instr(rawBlockAddr, ' ') + 1, 99), rawBlockAddr) blockName, 
 iif((instr(rawBlockAddr, ' ') - 1) <> LENGTH(ltrim(rtrim(substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ') - 1), '1234567890'), '123456789'))
     OR instr(rawBlockAddr, ' ') = 2, substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ')-1), "") flatNumber, 
 instr(rawBlockAddr, ' ') - 1 - LENGTH(ltrim(rtrim(substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ') - 1), '1234567890'), '123456789')) numDigits, 
 ltrim(rtrim(substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ') - 1), '1234567890'), '123456789') nonNumericBit, 
 REPLACE(substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ') - 1), ltrim(rtrim(substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ') - 1), '1234567890'), '123456789'), "") numericBit, 
 iif(LENGTH(ltrim(rtrim(substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ') - 1), '1234567890'), '123456789')) = 0, 0, instr(rawBlockAddr, ltrim(rtrim(substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ') - 1), '1234567890'), '123456789'))) nonNumericPos, 
 LENGTH(ltrim(rtrim(substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ') - 1), '1234567890'), '123456789')) = 0 justNumbers, 
 (instr(rawBlockAddr, ' ') - 1) <> LENGTH(ltrim(rtrim(substr(rawBlockAddr, 1, instr(rawBlockAddr, ' ') - 1), '1234567890'), '123456789')) hasNumbers
FROM tempaddr6;

-- 7a summarise block number details

DROP TABLE IF EXISTS tempaddr7a;


CREATE TEMP TABLE tempaddr7a AS
SELECT blockName,
       max(numDigits) numDigits,
       min(justNumbers) justNumbers,
       max(hasNumbers) hasNumbers
FROM tempaddr7
WHERE hasNumbers = 1
GROUP BY blockName;

-- work out sortable addresses within blocks for TTW software

DROP TABLE IF EXISTS tempaddr8;


CREATE TEMP TABLE tempaddr8 AS
SELECT t.electorKey,
       t.blockName,
       t.flatNumber,
       iif(flatnumber = '', '', concat(iif(flatSep IS NULL, '', concat(flatSep, ' ')), flatNumber)) addrInBlock,
       iif(flatnumber = '', '', concat(iif(flatSep IS NULL, '', concat(flatSep, ' ')), iif(nonNumericPos = 1, nonNumericBit, ''), iif(numericBit = '', '', substr(concat('000000', trim(numericBit)),-ta.numDigits, ta.numDigits)), iif(nonNumericPos>1, nonNumericBit, ''))) sortableAddrInBlock
FROM tempaddr7 t
LEFT OUTER JOIN tempaddr7a ta ON ta.blockName = t.blockName ;

-- stage 9 extract street and number in street from streetAddress

DROP TABLE IF EXISTS tempaddr9;


CREATE TEMP TABLE tempaddr9 AS
SELECT electorKey,
       postcode,
       REPLACE(firstPart, "|", " ") firstPart,
       streetAddress,
       iif(instr('123456789', substr(streetAddress, 1, 1)) = 0, streetAddress, iif(instr('123456789-', substr(streetAddress, instr(streetAddress, " ") + 1, 1)) > 0, trim(streetAddress, '1234567890 -'), substr(streetAddress, instr(streetAddress, " ")+ 1))) AS street,
       iif(instr('123456789', substr(streetAddress, 1, 1)) = 0, '', iif(instr('123456789-', substr(streetAddress, instr(streetAddress, " ") + 1, 1)) > 0, REPLACE(substr(streetAddress, 1, instr(streetAddress, trim(streetAddress, '1234567890 -'))-1), ' ', ''), substr(streetAddress, 1, instr(streetAddress, ' ')-1))) AS addressInStreet
FROM tempaddr4;

-- fix addresses where the firstPart has ended up with a street number in it
-- and the street is just bare, but there isn't a block. 
-- detect street number = there's no space and the first char is a digit

DROP TABLE IF EXISTS tempaddr_9a;


CREATE TEMP TABLE tempaddr_9a AS
SELECT t9.electorKey,
       t9.firstPart || ' ' || t9.streetAddress AS newStreetAddress,
       t9.firstPart AS newAddressInStreet,
       '' AS newFirstPart
FROM tempaddr9 t9
LEFT OUTER JOIN tempaddr8 t8 ON t8.electorKey = t9.electorKey
WHERE addressInStreet = ''
  AND instr(firstPart, ' ') = 0
  AND firstPart <> ''
  AND instr('123456789', substr(firstPart, 1, 1)) > 0
  AND t9.postcode <> ''
  AND t8.electorKey IS NULL;

-- update tempaddr9 with these

UPDATE tempaddr9
SET addressInStreet = newAddressInStreet,
    streetAddress = newStreetAddress,
    firstPart = ''
FROM tempaddr_9a ta
WHERE tempaddr9.electorKey = ta.electorKey ;

-- stage 10 join it all back together

DELETE
FROM addresses;


INSERT INTO addresses (electorKey, postcode, firstPart, streetAddress, street, addressInStreet, blockName, addrInBlock, sortableAddrInBlock, postcodeBlock, TTWAddress1, TTWAddress2, TTWAddress3)
SELECT t9.electorKey,
       postcode,
       t9.firstPart,
       streetAddress,
       street,
       addressInStreet,
       t8.blockName,
       t8.addrInBlock,
       t8.sortableAddrInBlock,
       concat_ws(" ", postcode, blockName) postcodeBlock,
       iif(blockName IS NULL, iif(firstPart = "", streetAddress, iif(instr('123456789', substr(firstPart, 1, 1)) > 0, concat('[', firstPart, ']'), firstPart)), concat(blockName, " ", sortableAddrInBlock)) TTWAddress1,
       iif(blockName IS NULL, iif(firstPart = "", "", streetaddress), streetAddress) TTWAddress2,
       '' TTWAddress3
FROM tempaddr9 t9
LEFT OUTER JOIN tempaddr8 t8 ON t9.electorKey = t8.electorKey;

-- select candidate "blocks"

DELETE
FROM candidateBlocks;


INSERT INTO candidateBlocks (a1, subaddresses)
SELECT substr(trim(TTWAddress1, '[]'), instr(trim(TTWAddress1, '[]'), ' ') + 1) a1,
       count(DISTINCT TTWaddress1) subaddresses
FROM addresses
WHERE substr(TTWAddress1, 1, 1) = '['
GROUP BY a1
HAVING count(DISTINCT TTWaddress1) > 9;