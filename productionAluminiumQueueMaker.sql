USE [smartshade]
GO
/****** Object:  StoredProcedure [dbo].[web_productionAluminumQueueMaker]    Script Date: 7/13/2022 9:18:03 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
ALTER PROCEDURE [dbo].[web_productionAluminumQueueMaker]
		@queueID int = 15,
		@productType NVARCHAR(50),
		@returnData NVARCHAR(50),
		@materialLength DECIMAL(18,3),
		@maxUnitCount int
AS
BEGIN



--DECLARE @queueID int = 15
--DECLARE @productType NVARCHAR(50) = 'HEAVY DUTY'
--DECLARE @returnData NVARCHAR(50) = 'TRACKS'
--DECLARE @materialLength DECIMAL(18,3) = 276.000
--DECLARE @maxUnitCount int = 20



--**GET LIST OF EVERYTHING IN BOX JOB QUEUE**--
IF OBJECT_ID('tempdb..#tempW') IS NOT NULL DROP TABLE #tempW

	CREATE TABLE #tempW
	(ID INT IDENTITY(1, 1) primary key ,
	jobNumber nvarchar(max),
	wizardID nvarchar(max),
	unitCount int)


--DECLARE @listStr NVARCHAR(MAX)

INSERT INTO #tempW
SELECT TOP(100)productionQueueContainerDetails.jobNumber, NULL, NULL
FROM            productionDepartmentPosition INNER JOIN
                         productionQueueContainerDetails ON productionDepartmentPosition.containerID = productionQueueContainerDetails.containerID
WHERE productionDepartmentPosition.queueID = @queueID AND productionDepartmentPosition.queueFinished = 0 AND NOT EXISTS (SELECT id FROM productionDepartmentStatus WHERE deptPosRowId =  productionDepartmentPosition.id AND statusMessage LIKE '%SKIP %')
ORDER BY productionDepartmentPosition.queuePosition ASC


--SELECT @jobNumber
--return


UPDATE #tempW SET wizardID = (SELECT TOP(1)wizardID FROM wizardManager WHERE jobNumber = #tempW.jobNumber)

UPDATE #tempW SET unitCount = (SELECT COUNT(*) FROM wizardUnitStatus WHERE wizardID = #tempW.wizardID)

--SELECT * FROM #tempW
--return


--Create table to store jobs that are skipped so they can be promoted to BOX CUT
IF OBJECT_ID('tempdb..#tempWDone') IS NOT NULL DROP TABLE #tempWDone

	CREATE TABLE #tempWDone
	(
	ID int,
	jobNumber nvarchar(max),
	wizardID nvarchar(max),
	unitCount int,
	unitIDDelete int
	)

--Remove Cutdowns since they don't use new stock
DELETE FROM #tempW 
OUTPUT DELETED.*, NULL INTO #tempWDone
WHERE EXISTS (SELECT crNumber FROM crContainerList WHERE crNumber = #tempW.jobNumber AND crContainerList.changeInventory = 0)

--Mark removed Cutdowns as complete so they can move to BOX CUT
UPDATE #tempWDone SET unitIDDelete = (SELECT TOP(1) unitID FROM wizardUnitDetails WHERE wizardUnitDetails.wizardID = #tempWDone.wizardID)
INSERT INTO productionAluminiumUnitCutQueue SELECT unitIDDelete, @queueID,@returnData, 1, wizardID FROM #tempWDone WHERE NOT EXISTS (SELECT id FROM productionAluminiumUnitCutQueue WHERE unitID = unitIDDelete AND deptID = @queueID AND deptCut = @returnData)


--**CONDENSE LIST DOWN TO 20 UNITS**--
IF OBJECT_ID('tempdb..#tempS') IS NOT NULL DROP TABLE #tempS

	CREATE TABLE #tempS
	(ID INT IDENTITY(1, 1) primary key ,
	wizardID nvarchar(max),
	unitCount int)

INSERT INTO #tempS
SELECT wizardID, unitCount FROM(
SELECT wizardID, unitCount, (SELECT sum(unitCount) FROM #tempW WHERE ID<=T.ID) as 'Sum'
FROM #tempW T) M
WHERE sum <= @maxUnitCount

--select * from #tempS
--return

--Create table to store jobs that are skipped so they can be promoted to BOX CUT
IF OBJECT_ID('tempdb..#tempSDone') IS NOT NULL DROP TABLE #tempSDone

	CREATE TABLE #tempSDone
	(
	ID int,
	wizardID nvarchar(max),
	unitCount int,
	unitIDDelete int
	)

--SELECT * FROM #tempS
--Remove Remakes that don't require a part that goes into Aluminum Queue
IF @returnData = 'BOXCUT'
BEGIN
	DELETE FROM #tempS 
	OUTPUT DELETED.*, NULL INTO #tempSDone
	WHERE EXISTS (SELECT id FROM crContainerDetails WHERE crContainerDetails.wizardGUID = #tempS.wizardID) 
	AND NOT EXISTS (SELECT crContainerDetails.id FROM crContainerDetails INNER JOIN inventoryMasterPartsList ON inventoryMasterPartsList.id = crContainerDetails.partID 
	WHERE crContainerDetails.wizardGUID = #tempS.wizardID AND crContainerDetails.assemblyName LIKE '%Container%' AND inventoryMasterPartsList.[type] LIKE '%Extrusion%')
	AND NOT EXISTS (SELECT id FROM crContainerDetails WHERE crContainerDetails.wizardGUID = #tempS.wizardID AND partID = -2)
END
IF @returnData = 'HEMBAR'
BEGIN
	DELETE FROM #tempS 
	WHERE EXISTS (SELECT id FROM crContainerDetails WHERE crContainerDetails.wizardGUID = #tempS.wizardID) 
	AND NOT EXISTS (SELECT crContainerDetails.id FROM crContainerDetails INNER JOIN inventoryMasterPartsList ON inventoryMasterPartsList.id = crContainerDetails.partID 
	WHERE crContainerDetails.wizardGUID = #tempS.wizardID AND crContainerDetails.assemblyName LIKE '%Bottom%' AND inventoryMasterPartsList.[type] = 'Hem Bar')
	AND NOT EXISTS (SELECT id FROM crContainerDetails WHERE crContainerDetails.wizardGUID = #tempS.wizardID AND partID = -2)
END
IF @returnData = 'TRACKS'
BEGIN
	DELETE FROM #tempS 
	WHERE EXISTS (SELECT id FROM crContainerDetails WHERE crContainerDetails.wizardGUID = #tempS.wizardID) 
	AND NOT EXISTS (SELECT crContainerDetails.id FROM crContainerDetails INNER JOIN inventoryMasterPartsList ON inventoryMasterPartsList.id = crContainerDetails.partID 
	WHERE crContainerDetails.wizardGUID = #tempS.wizardID AND crContainerDetails.assemblyName LIKE '%Guide Assembly - FRT%' AND (inventoryMasterPartsList.itemName = 'FRT Fixed' OR inventoryMasterPartsList.itemName = 'FRT Removable'))
	AND NOT EXISTS (SELECT id FROM crContainerDetails WHERE crContainerDetails.wizardGUID = #tempS.wizardID AND partID = -2)
END
IF @returnData = 'LCHANNEL'
BEGIN
	DELETE FROM #tempS 
	WHERE EXISTS (SELECT id FROM crContainerDetails WHERE crContainerDetails.wizardGUID = #tempS.wizardID) 
	AND NOT EXISTS (SELECT crContainerDetails.id FROM crContainerDetails INNER JOIN inventoryMasterPartsList ON inventoryMasterPartsList.id = crContainerDetails.partID 
	WHERE crContainerDetails.wizardGUID = #temps.wizardID AND crContainerDetails.assemblyName LIKE '%Guide Assembly - FRT%' AND inventoryMasterPartsList.itemName = 'L-Mounting Channel')
	AND NOT EXISTS (SELECT id FROM crContainerDetails WHERE crContainerDetails.wizardGUID = #tempS.wizardID AND partID = -2)
END
--Mark units with no box as complete so they can move to BOX CUT
UPDATE #tempSDone SET unitIDDelete = (SELECT TOP(1) unitID FROM wizardUnitDetails WHERE wizardUnitDetails.wizardID = #tempSDone.wizardID)
INSERT INTO productionAluminiumUnitCutQueue SELECT unitIDDelete, @queueID,@returnData, 1, wizardID FROM #tempSDone WHERE NOT EXISTS (SELECT id FROM productionAluminiumUnitCutQueue WHERE unitID = unitIDDelete AND deptID = @queueID AND deptCut = @returnData)
--SELECT * FROM #tempSDone
--SELECT * FROM #tempS
DECLARE @wizIdList NVARCHAR(max) 
SELECT @wizIdList = COALESCE(@wizIdList + ',', '') + wizardID 
FROM #tempS

--SELECT @wizIdList
--return

	IF OBJECT_ID('tempdb..#tempN') IS NOT NULL DROP TABLE #tempN

	CREATE TABLE #tempN
	(rowID INT IDENTITY(1, 1) primary key ,
	id int,
	wizardID nvarchar(max),
	unitNumber int,
	qtyOfUnit  int,
	unitType nvarchar(max),
	unitProduct nvarchar(max),
	shadeType nvarchar(max),
	deduction nvarchar(max),
	width decimal(18,3),
	[drop] decimal(18,3),
	handing nvarchar(50),
	widthForOptimizer decimal(18,3),
	dropForOptimizer decimal(18,3)
	)


INSERT INTO #tempN SELECT wus.id, wus.wizardID, wus.unitNumber, wus.qtyOfUnit, wus.unitType, wus.unitProduct,NULL,NULL,0,0.0,NULL,NULL,NULL
FROM wizardUnitStatus wus
WHERE wus.wizardID  IN 
(SELECT convert(nvarchar(MAX), value) FROM string_split(@wizIdList,',')) 

--SELECT * FROM #tempN
--return

IF @returnData  = 'LCHANNEL'
BEGIN
DELETE FROM #tempN WHERE #tempN.wizardID NOT IN (SELECT wizardID FROM wizardUnitDetails WHERE unitID = #tempN.id AND wizardID = #tempN.wizardID AND (attributeValue LIKE '%2 L CHANNEL%' OR attributeValue LIKE '%1 L CHANNEL%'))
END

--send SHYs straight to Box Cut
INSERT INTO productionAluminiumUnitCutQueue SELECT id, @queueID,@returnData, 1, wizardID FROM #tempN WHERE unitProduct LIKE 'SHY%' AND NOT EXISTS (SELECT id FROM productionAluminiumUnitCutQueue WHERE unitID = id AND deptID = @queueID AND deptCut = @returnData)
DELETE FROM #tempN WHERE unitProduct LIKE 'SHY%'

UPDATE #tempN SET shadeType = (SELECT TOP(1)shadeType FROM cachedShadeType WHERE wizardID = #tempN.wizardID order by id desc)
UPDATE #tempN SET shadeType = (SELECT TOP(1)shadeType FROM cachedShadeType WHERE wizardID = #tempN.wizardID  and unitnumber = 2 order by id desc) WHERE LEN(shadeType) < 1
UPDATE #tempN SET shadeType = (SELECT dbo.getShadeType(#tempN.wizardID,#tempN.unitNumber )) WHERE unitNumber = 1 AND shadeType IS NULL OR LEN(shadeType) < 1

UPDATE #tempN SET shadeType = CASE WHEN unitProduct LIKE '%Adjustable Hem Bar%' THEN shadeType + ' - Adjustable Hem Bar' ELSE shadeType END
UPDATE #tempN SET shadeType = REPLACE(shadeType,' Over 204.125', '')


UPDATE #tempN SET width = CONVERT(DECIMAL(18,3),(SELECT TOP(1)attributeValue FROM wizardUnitDetails WHERE wizardID = #tempN.wizardID AND unitID = #tempN.id and wizardUnitDetails.attributeName ='width' ORDER BY wizardUnitDetails.id DESC))
UPDATE #tempN SET [drop] = CONVERT(DECIMAL(18,3),(SELECT TOP(1) attributeValue FROM wizardUnitDetails WHERE  wizardID = #tempN.wizardID AND unitID = #tempN.id and wizardUnitDetails.attributeName ='drop' ORDER BY wizardUnitDetails.id DESC))

UPDATE #tempN SET deduction =  (SELECT dbo.getCutVariables(@returnData,shadeType,width,[drop]))
--UPDATE #tempN SET deduction = CASE WHEN deduction IS NULL THEN (SELECT dbo.getCutVariables(REPLACE(@returnData, 'HEMBAR', 'AdjHemBar'), shadeType, width, [drop])) ELSE deduction END
UPDATE #tempN SET deduction = CASE WHEN deduction IS NULL THEN (SELECT dbo.getCutVariables(@returnData, REPLACE(shadeType, ' - Adjustable Hem Bar', ''),width,[drop])) ELSE deduction END

UPDATE #tempN SET handing = (SELECT TOP(1) attributeValue FROM wizardUnitDetails WHERE  wizardID = #tempN.wizardID AND unitID = #tempN.id and wizardUnitDetails.attributeName ='handing' ORDER BY wizardUnitDetails.id DESC)

UPDATE #tempN SET widthForOptimizer = width + deduction + 0.250
UPDATE #tempN SET dropForOptimizer = [drop] + deduction + 0.250

--SELECT * FROM #tempN WHERE unitProduct LIKE '%' + @productType + '%'
--ORDER BY rowID ASC


IF OBJECT_ID('tempdb..#tempOPT') IS NOT NULL DROP TABLE #tempOPT

	CREATE TABLE #tempOPT
	(rowID INT IDENTITY(1, 1) primary key,
	unitList nvarchar(max),
	cutList nvarchar(max),
	totalCut decimal(18,3),
	waste decimal(18,3) NULL
	)

IF OBJECT_ID('tempdb..#tempUnitID') IS NOT NULL DROP TABLE #tempUnitID

	CREATE TABLE #tempUnitID
	(rowID INT IDENTITY(1, 1) primary key,
	unitID int
	)


DECLARE @unitID INT;
DECLARE @width DECIMAL(18,3);


DECLARE optCur CURSOR FAST_FORWARD FOR
    SELECT id
    FROM   #tempN WHERE unitProduct LIKE '%' + @productType + '%'
ORDER BY rowID ASC;
 
OPEN optCur
FETCH NEXT FROM optCur INTO @unitID
 
WHILE @@FETCH_STATUS = 0
BEGIN

	--Get width from current row
	IF @returnData IN ('TRACKS', 'LCHANNEL') SET @width = (SELECT dropForOptimizer FROM #tempN WHERE id= @unitID)
	
	IF @returnData NOT IN ('TRACKS', 'LCHANNEL') SET @width = (SELECT widthForOptimizer FROM #tempN WHERE id= @unitID)
	
   --if tempopt is empty then insert a row
   IF (SELECT COUNT(*) FROM #tempOPT) = 0
   BEGIN
  
   IF @returnData IN ('TRACKS', 'LCHANNEL')
   BEGIN
   INSERT INTO #tempOPT (unitList, cutList, totalCut) SELECT @unitID, (SELECT dropForOptimizer FROM #tempN WHERE id = @unitID),(SELECT dropForOptimizer FROM #tempN WHERE id = @unitID) WHERE @unitID NOT IN (SELECT unitID FROM #tempUnitID)
   INSERT INTO #tempUnitID (unitID) VALUES (@unitID)
   END
   
   IF @returnData NOT IN ('TRACKS', 'LCHANNEL')
   BEGIN
   INSERT INTO #tempOPT (unitList, cutList, totalCut) SELECT @unitID, (SELECT widthForOptimizer FROM #tempN WHERE id = @unitID),(SELECT widthForOptimizer FROM #tempN WHERE id = @unitID) WHERE @unitID NOT IN (SELECT unitID FROM #tempUnitID)
   INSERT INTO #tempUnitID (unitID) VALUES (@unitID)
   END

   CONTINUE
   END
   
  
   DECLARE @totalCut DECIMAL(18,3)
   DECLARE @rowCount int = 1
   IF (SELECT COUNT(*) FROM #tempOPT) > 0
   BEGIN
   
	WHILE (@rowCount <= (SELECT COUNT(*) FROM #tempOPT))
		BEGIN
			SET @totalCut = (SELECT totalCut FROM #tempOPT WHERE rowID = @rowCount)

			IF (@totalCut + @width) <= @materialLength
			BEGIN
			UPDATE #tempOPT SET totalCut = (@totalCut + @width), unitList = (COALESCE(unitList+',' ,'') + CAST(@unitID AS NVARCHAR(50))), cutList = (COALESCE(cutList+',' ,'') + CAST(@width AS NVARCHAR(50))) WHERE rowID = @rowCount AND @unitID NOT IN (SELECT unitID FROM #tempUnitID)
			INSERT INTO #tempUnitID (unitID) VALUES (@unitID)
			
			END

			SET @rowCount = @rowCount +1

			IF (@rowCount > (SELECT COUNT(*) FROM #tempOPT))
			BEGIN

			   IF @returnData IN ('TRACKS', 'LCHANNEL')
			   BEGIN
			   INSERT INTO #tempOPT (unitList, cutList, totalCut) SELECT @unitID, (SELECT dropForOptimizer FROM #tempN WHERE id = @unitID),(SELECT dropForOptimizer FROM #tempN WHERE id = @unitID) WHERE @unitID NOT IN (SELECT unitID FROM #tempUnitID)
			   END
   
			   IF @returnData NOT IN ('TRACKS', 'LCHANNEL')
			   BEGIN
			   INSERT INTO #tempOPT (unitList, cutList, totalCut) SELECT @unitID, (SELECT widthForOptimizer FROM #tempN WHERE id = @unitID),(SELECT widthForOptimizer FROM #tempN WHERE id = @unitID) WHERE @unitID NOT IN (SELECT unitID FROM #tempUnitID)
			   END

			
			INSERT INTO #tempUnitID (unitID) VALUES (@unitID)
			
			END

			
		 END
     END

   FETCH NEXT FROM optCur INTO @unitID
END
CLOSE optCur
DEALLOCATE optCur

UPDATE #tempOPT SET waste = @materialLength - totalCut

DECLARE @batchID NVARCHAR(MAX)
SET @batchID = NEWID()  

--SELECT * FROM #tempOPT
--return

DECLARE @listStrFInal NVARCHAR(MAX)
SELECT @listStrFInal = COALESCE(@listStrFInal+',' ,'') + #tempOPT.unitList
FROM #tempOPT WHERE cutList IS NOT NULL

SET @listStrFInal = @listStrFInal + ','

--SELECT @listStrFInal
--SELECT * FROM #tempN

	IF OBJECT_ID('tempdb..#tempBatch') IS NOT NULL DROP TABLE #tempBatch

	CREATE TABLE #tempBatch
	(batchID nvarchar(max),
	productType nvarchar(max),
	returnData nvarchar(max),
	batchParent int,
	batchOrder INT IDENTITY(1, 1) primary key,
	unitID int,
	cutLength DECIMAL(18,3),
	totalCut DECIMAL(18,3),
	waste DECIMAL(18,3))



DECLARE @pos INT = 0
DECLARE @len INT = 0
DECLARE @value INT = 0

WHILE CHARINDEX(',', @listStrFInal, @pos+1)>0
BEGIN
    set @len = CHARINDEX(',', @listStrFInal, @pos+1) - @pos
    set @value = SUBSTRING(@listStrFInal, @pos, @len)
            
    INSERT INTO #tempBatch SELECT @batchID,@productType,@returnData,NULL,@value, NULL,NULL,NULL WHERE NOT EXISTS (SELECT id FROM productionAluminiumUnitCutQueue WHERE unitID = @value AND deptID = @queueID AND deptCut = @returnData)        
    INSERT INTO productionAluminiumUnitCutQueue SELECT @value, @queueID,@returnData, 0, (SELECT wizardID FROM #tempN WHERE id = @value) WHERE NOT EXISTS (SELECT id FROM productionAluminiumUnitCutQueue WHERE unitID = @value AND deptID = @queueID AND deptCut = @returnData)
	
    set @pos = CHARINDEX(',', @listStrFInal, @pos+@len) +1
END

UPDATE #tempBatch SET batchParent = (SELECT rowID FROM #tempOPT WHERE unitList LIKE '%' + CAST(#tempBatch.unitID AS NVARCHAR(50)) + '%' )
UPDATE #tempBatch SET totalCut = (SELECT totalCut FROM #tempOPT WHERE unitList LIKE '%' + CAST(#tempBatch.unitID AS NVARCHAR(50)) + '%' )
UPDATE #tempBatch SET waste = (SELECT waste FROM #tempOPT WHERE unitList LIKE '%' + CAST(#tempBatch.unitID AS NVARCHAR(50)) + '%' )
IF @returnData IN ('TRACKS', 'LCHANNEL') UPDATE #tempBatch SET cutLength = (SELECT dropForOptimizer FROM #tempN WHERE id = #tempBatch.unitID)

IF @returnData NOT IN ('TRACKS', 'LCHANNEL') UPDATE #tempBatch SET cutLength = (SELECT widthForOptimizer FROM #tempN WHERE id = #tempBatch.unitID)

INSERT INTO productionAluminumBatchReport
SELECT * FROM #tempBatch

END
