IF  EXISTS (
        SELECT type_desc, type
        FROM sys.procedures WITH(NOLOCK)
        WHERE NAME = 'DonorProfileStandardQueryExport'
            AND type = 'P'
      )
BEGIN
	DROP PROCEDURE dbo.DonorProfileStandardQueryExport
END
Go
	CREATE PROCEDURE [dbo].[DonorProfileStandardQueryExport] 
		-- Add the parameters for the stored procedure here
		@testdata xml = NULL,
		@company_name NVARCHAR(100), 
		@company_address NVARCHAR(100),
		@company_phone NVARCHAR(100),
		@company_email NVARCHAR(100),
		@fiscal_start_date DATETIME,
		@campaign_id uniqueidentifier,
		@campaign_for_avgs uniqueidentifier,
		@topPercentToUseForSchoolAverageDonation INT ,
		@base_url NVARCHAR(100),
		--@RfmRecencyMaxQuintileYearSelection NVARCHAR(25) ='Pervious Fiscal Year (Recommended)',
		--@RfmMaxQuintileYearCurrentFiscalYear NVARCHAR(25)='Current Fiscal Year',
		@DonationTemplateID uniqueidentifier ,
		@daf_system_class_id int,
		@daf_organization_type nvarchar(100)
	AS
	BEGIN
		DECLARE
		@ListDonorProfileIds DonorProfileIDList, 
		@IncludeTopDonationAverageInSuggestedAsString BIT,
		@top_average_string varchar(500)
		,@start_string DATETIME
		,@one_start DATETIME  
		,@one_end DATETIME
		,@two_start DATETIME 
		,@two_end DATETIME
		,@three_start DATETIME
		,@three_end DATETIME
		,@four_start DateTime
		,@four_end  DateTime
		,@five_start DateTime
		,@five_end  DateTime
		,@six_start  DateTime
		,@six_end   DateTime
		,@seven_start DateTime
		,@seven_end  DateTime
		,@eight_start DateTime
		,@eight_end DateTime
		,@nine_start DateTime
		,@nine_end  DateTime
		,@end_string DATETIME = '2023-06-30'
		--------------------------------------
	
		INSERT INTO @ListDonorProfileIds (ProfileID)
		SELECT
			GuidValue = XmlDataItem.value('.', 'uniqueidentifier')
		FROM
			@testdata.nodes('/GuidList/Guid') AS XmlData(XmlDataItem);

			--select * from @ListDonorProfileIds

		
	-----------------------------------------------Calculate start and end dates so that it can used in calculations---------------------------------------------------------------------------------
		IF @fiscal_start_date > GETDATE()
			SET @fiscal_start_date = DATEADD(year,-1,@fiscal_start_date)

		SET @start_string = @fiscal_start_date
		SET @end_string = DATEADD(year, 1, @fiscal_start_date)
		SET @end_string = DATEADD(day,-1,@end_string)

		SET @one_start  = DATEADD(year, -1, @fiscal_start_date)
		SET @one_end = DATEADD(day,-1,@fiscal_start_date)

		SET @two_start = DATEADD(year,-2, @fiscal_start_date)
		SET @two_end =  DATEADD(DAY,-1, @one_start)

		SET @three_start = DATEADD(year,-3, @fiscal_start_date)
		SET @three_end = DATEADD(DAY,-1, @two_start)

		SET @four_start = DATEADD(year,-4, @fiscal_start_date)
		SET @four_end = DATEADD(DAY,-1, @three_start)

		SET @five_start = DATEADD(year,-5, @fiscal_start_date)
		SET @five_end = DATEADD(DAY,-1, @four_start)

		SET @six_start = DATEADD(year,-6, @fiscal_start_date)
		SET @six_end = DATEADD(DAY,-1, @five_start)

		SET @seven_start = DATEADD(year,-7, @fiscal_start_date)
		SET @seven_end = DATEADD(DAY,-1, @six_start)

		SET @eight_start = DATEADD(year,-8, @fiscal_start_date)
		SET @eight_end = DATEADD(DAY,-1, @seven_start)

		SET @nine_start = DATEADD(year,-9, @fiscal_start_date)
		SET @nine_end = DATEADD(DAY,-1, @eight_start)

		---------------------------------------------Calculate Giving Levels----------------------------------------------------------------------------------------------------------------
		DECLARE @giving_levels_no_links NVARCHAR(100),@giving_levels_with_titles_no_links NVARCHAR(500)	,@giving_levels_with_links NVARCHAR(500)

		SELECT @giving_levels_no_links = STRING_AGG('$' + CAST(DT.Amount AS NVARCHAR) + '|', '') 
			  ,@giving_levels_with_titles_no_links = STRING_AGG(DT.Title+':'+CAST(DT.Amount AS NVARCHAR)+' | ','')
		FROM [dbo].[tw_DonationTemplateGivingLevel] DT
		WHERE DonationTemplateID = @DonationTemplateID
		AND Active = 1
		---------------------------------------------Calculate Campaign Details----------------------------------------------------------------------------------------------------------------
		DECLARE @campaign_title NVARCHAR(100),@campaign_goal FLOAT
		,@campaign_amountraised FLOAT,@donation_percent FLOAT
		,@pct_to_take INT
		,@take_number INT = 5
		,@all_school_average_donation_previous_FY_unrounded FLOAT
		,@all_school_top_pct_average_donation_previous_FY_unrounded FLOAT
		,@all_school_average_donation_previous_FY_rounded FLOAT
		,@all_school_top_pct_average_donation_previous_FY_rounded FLOAT
		,@donation_url nvarchar(250)

		SELECT @campaign_title = Title,@campaign_goal = GoalAmount
		FROM tw_DonationCampaign WHERE tw_DonationCampaign.DonationCampaignID =@campaign_id


		SELECT @campaign_amountraised = ISNULL(SUM(Amount),0) 
		FROM dbo.tw_Donation WHERE DonationCampaignID = @campaign_id

		SET @donation_percent =Round(ISNULL((@campaign_amountraised/NULLIF(@campaign_goal,0) *100),0),0)
	
		Declare @all_school_donations_previous_FY TABLE  
		(  
			Amount Money  
		)  
	
		INSERT INTO @all_school_donations_previous_FY
		SELECT Amount 
		FROM dbo.tw_Donation d
		WHERE d.DonatedOn >= DATEADD(year, -1, @fiscal_start_date)
		AND d.DonatedOn <= DATEADD(year, -1, @end_string)
		AND (
			(@campaign_for_avgs IS NULL OR @campaign_for_avgs = '00000000-0000-0000-0000-000000000000') OR
			(d.DonationCampaignID = @campaign_for_avgs)
		)
	
		IF EXISTS( SELECT TOP 1 1 FROM @all_school_donations_previous_FY)
		BEGIN
			IF (@topPercentToUseForSchoolAverageDonation = 0)
				SET @pct_to_take = 1
			ELSE
				SET @pct_to_take = @topPercentToUseForSchoolAverageDonation

				SELECT @take_number = (COUNT(1) * @pct_to_take)/100
				FROM @all_school_donations_previous_FY

				SELECT @take_number = 
					CASE 
						WHEN @take_number >= 1 AND @take_number <= COUNT(*) THEN @take_number
						WHEN COUNT(*) > 0 THEN COUNT(*)
						ELSE 1
					END
				FROM @all_school_donations_previous_FY
				--------------------------------------------------
				SELECT @all_school_average_donation_previous_FY_unrounded =
				CASE 
					WHEN COUNT(*) > 0 THEN SUM(Amount) / CAST(COUNT(1) AS DECIMAL(18, 2))
					ELSE 0 -- 
				END
					FROM @all_school_donations_previous_FY
				------------------------------------------------------------------
				SELECT @all_school_top_pct_average_donation_previous_FY_unrounded =
				CASE 
				WHEN COUNT(1) > 0 THEN 
					(SELECT SUM(Amount) / CAST(@take_number AS DECIMAL(18, 2))
					FROM (SELECT TOP (@take_number) Amount
						  FROM @all_school_donations_previous_FY
						  ORDER BY Amount DESC) AS top_donations)
				ELSE 0 
				END
			-------------------------------------------------------------------
			SELECT @all_school_average_donation_previous_FY_rounded =
			CASE 
				WHEN @all_school_average_donation_previous_FY_unrounded IS NOT NULL THEN 
					CEILING(@all_school_average_donation_previous_FY_unrounded / 10.0) * 10
				ELSE 0 -- or 0 or any default value as per your requirement
			END
			------------------------------------------------------------------------------
			SELECT @all_school_top_pct_average_donation_previous_FY_rounded =
			CASE 
				WHEN @all_school_top_pct_average_donation_previous_FY_unrounded IS NOT NULL THEN 
					CEILING(@all_school_top_pct_average_donation_previous_FY_unrounded / 10.0) * 10
				ELSE 0
			END
		
		END
		--------------------------------------------------------------------------------
		IF ((@IncludeTopDonationAverageInSuggestedAsString = 1) AND (EXISTS( SELECT TOP 1 1 FROM @all_school_donations_previous_FY)))
		BEGIN
		   SET @top_average_string = 'Last year, our top contributors gave on average '+ CONVERT(NVARCHAR(20), @all_school_top_pct_average_donation_previous_FY_rounded)+ 'Please consider a gift that is comfortable for your family and know that it is deeply appreciated and spent wisely. Any amount benefits our school tremendously, but to help you get started, here are some suggested amounts:'
		END
		ELSE
		BEGIN
			SET @top_average_string = ''
		END
		SET @donation_url = @base_url+'/forms/donation/'+ @campaign_title
	
		---------------------------------------------Main Query----------------------------------------------------------------------------------------------------------------
			 SELECT DISTINCT
			 dp.DonorProfileID
			,@company_name AS 'SchoolName'
			,@company_address AS 'SchoolAddress'
			,@company_phone AS 'SchoolPhone'
			,@company_email AS 'SchoolEmailAddress'
			,dp.CalculatedGivingName AS 'ActualGivingName'
			,dp.CalculatedGreeting AS 'ActualGreeting'
			,a.SalutationFirstname + a.SalutationLastname AS 'ActualAddressSalutation'
			,a.FamilySalutation AS 'FamilySalutation'
			,ISNULL(a.Address1,'') + ISNULL(a.Address2,'') +' '+ ISNULL(a.City,'') +' '+ ISNULL(a.Region,'') +' '+ISNULL(a.PostalCode,'') AS 'RecipientAddress'
			,a.Address1 AS 'Address1'
			,a.Address2 AS 'Address2'
			,a.City AS 'City'
			,a.Region AS 'Region'
			,a.PostalCode AS 'PostalCode'
			,a.CountryCode AS 'CountryCode'
			,eid.Email As 'ActualEmailAddressTitle'
			,ph.Number As 'ActualPhoneNumberTitle'
			,CASE 
					WHEN dp.IsDonorAdvisedFund = 1 
						OR 
						(EXISTS (SELECT 1 FROM tw_Company WHERE CompanyID = (SELECT TOP 1 ParentID FROM tw_DonorProfileJoin WHERE [Default] = 1 AND DonorProfileID = dp.DonorProfileID)) 
						AND (SELECT OrganizationType FROM tw_Company WHERE CompanyID = (SELECT TOP 1 ParentID FROM [dbo].[tw_DonorProfileJoin]tw_DonorProfileJoin WHERE [Default] = 1 AND DonorProfileID = dp.DonorProfileID)) = @daf_organization_type)
						OR 
						(EXISTS (SELECT 1 FROM tw_DonorProfileJoin WHERE [Default] = 1 AND DonorProfileID = dp.DonorProfileID) 
						AND (SELECT ParentSystemClassID FROM tw_DonorProfileJoin WHERE [Default] = 1 AND DonorProfileID = dp.DonorProfileID) = @daf_system_class_id)
						THEN CAST(1 AS BIT)
					ELSE CAST(ISNULL(dp.IsDonorAdvisedFund, 0) AS BIT)
				END 
			  AS 'IsDonorAdvisedFund'
			,'' As'SmartTextForRoles'
			,'' As'AllSmartRoles'
			,'' As'DonorRoles'
			,'' As 'DonorSubRoles'
			,'' As 'FirstNamesOfEnrolledWards'
			,'' As 'FirstNamesOfAlumniGrandchildren'
			,'' As 'RFM'
			,(SELECT COALESCE(
					(
						SELECT 
							CASE 
								WHEN max(d.DonatedOn) > @fiscal_start_date THEN 'Current Donor'
								WHEN max(d.DonatedOn) > DATEADD(YEAR, -1, @fiscal_start_date) THEN 'Lapsing'
								WHEN max(d.DonatedOn) > DATEADD(YEAR, -3, @fiscal_start_date) THEN 'Lapsed'
								ELSE 'Former Donor'
							END AS DonorStatus
						FROM 
							dbo.tw_Donation d WITH(NOLOCK)
						WHERE 
							d.DonorProfileID = dp.DonorProfileID
						GROUP BY 
							DonorProfileID
					), 
					'Never Donated'
				)) AS DonorStatus
			,(SELECT 
				COUNT(DISTINCT 
					  CASE 
						  WHEN MONTH(DonatedOn) >=MONTH(@fiscal_start_date) THEN YEAR(DonatedOn)
						  ELSE YEAR(DATEADD(month, Month(@fiscal_start_date)-1, DonatedOn)) 
					  END
				) AS TotalDonationYears
				FROM 
					dbo.tw_Donation

				WHERE DonorProfileID = dp.DonorProfileID) As 'TotalYearsGiven'
			,0 As 'ConsecutiveYearsGiven'
			,'' As 'ConsecutiveYearsGivenForDisplay'
		
			,(SELECT ISNULL(count(DonatedOn),0)
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID  
					AND IsStock = 0 AND InKind = 0
					)  as 'NumberOfGiftsAndPledgesLifetime'
			,(SELECT count( DonatedOn)
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID  
					AND IsStock = 1
					)  as 'NumberOfStockDonationsLifetime'
			,(SELECT count( DonatedOn)
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID  
					AND InKind = 1
					)  as 'NumberOfInKindDonationsLifetime'

			,(SELECT SUM(Amount)
				FROM dbo.tw_Donation WITH(NOLOCK) WHERE DonorProfileID = dp.DonorProfileID ) AS 'LifetimeDonatedAmount'
			,'' AS 'LifetimeDonatedAmountFormatted'
			,(SELECT AVG(Amount)
				FROM dbo.tw_Donation WITH(NOLOCK) WHERE DonorProfileID = dp.DonorProfileID ) AS 'AverageDonationAmount'
			,'' AS 'AverageDonationAmountFormatted'

			,(SELECT TOP 1 DonatedOn 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					ORDER BY DonatedOn) as 'FirstDonationDate'
			,(SELECT TOP 1 Amount 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					ORDER BY DonatedOn) as 'FirstDonationAmount'
			,(SELECT TOP 1 Amount 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					ORDER BY DonatedOn) as 'FirstDonationAmount'
			,'' as 'FirstDonationAmountFormatted'
			,(SELECT TOP 1 Amount 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					ORDER BY DonatedOn desc) as 'LastDonationAmount'
			,'' as 'LastDonationAmountFormatted'
			,(SELECT TOP 1 DonatedOn 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					ORDER BY DonatedOn DESC) as 'LastDonationDate'
			,(SELECT MAX(Amount) 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID) as 'LargestDonationAmount'
			,'' as 'LargestDonationAmountFormatted'
			,(SELECT TOP 1 DonatedOn 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					ORDER BY Amount desc)  as 'LargestDonationDate'
		
			,(SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0)
			FROM 
				dbo.tw_Donation WITH(NOLOCK)
			WHERE 
				DonorProfileID = dp.DonorProfileID 
				AND DonatedOn >= @three_start
				AND DonatedOn <= @three_end)  AS 'DonatedPreviousThreeYears'
			,CONVERT(nvarchar(100),CONVERT(DATETIME, @start_string, 103),105) + ' - ' + CONVERT(nvarchar(100),CONVERT(DATETIME, @end_string, 103),105) as 'FiscalYearToDate'
			,(SELECT count(DonatedOn) 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @start_string
					AND DonatedOn <= @end_string AND InKind = 0 AND IsStock = 0) as 'NumberOfGiftsAndPledgesYearToDate'
			,(SELECT count(DonatedOn) 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @start_string
					AND DonatedOn <= @end_string  AND IsStock = 0) as 'NumberOfStockDonationsYearToDate'

			,(SELECT count(DonatedOn) 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @start_string
					AND DonatedOn <= @end_string  AND InKind = 0) as 'NumberOfInKindDonationsYearToDate'
			,(SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
			FROM 
				dbo.tw_Donation WITH(NOLOCK)
			WHERE 
				DonatedOn >= @start_string
				AND DonatedOn <= @end_string) as 'DonatedYearToDate'
			,(SELECT 
				FORMAT(COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0), 'C', 'en-US') AS TotalAmount
			FROM 
				dbo.tw_Donation WITH(NOLOCK)
			WHERE 
				DonatedOn >= @start_string
				AND DonatedOn <= @end_string) as 'DonatedYearToDateFormatted'
		
			,((((SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
	
				FROM 
					dbo.tw_Donation WITH(NOLOCK)
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @one_start
					AND DonatedOn <= @one_end) -
			(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @start_string
					AND DonatedOn <= @end_string))/(SELECT nullif(SUM(Amount),0) 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @start_string
					AND DonatedOn <= @end_string)) * 100
			 ) as 'PercentChangeFromLastFiscalYear'
			, CONVERT(nvarchar(100),CONVERT(DATETIME, @one_start, 103),105) +'-'+ CONVERT(nvarchar(100),CONVERT(DATETIME, @one_end, 103),105) as 'FiscalLastYear'
			,(SELECT COUNT(1) 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @one_start
					AND DonatedOn <= @one_end
					AND InKind = 0
					AND IsStock=0) as 'NumberOfGiftsAndPledgesLastFiscalYear'
			,(SELECT COUNT(1) 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @one_start
					AND DonatedOn <= @one_end
					AND IsStock=1) as 'NumberOfStockDonationsLastFiscalYear'
			,(SELECT COUNT(1) 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @one_start
					AND DonatedOn <= @one_end
					AND InKind = 1) as 'NumberOfInKindDonationsLastFiscalYear'
			,(SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
	
				FROM 
					dbo.tw_Donation WITH(NOLOCK)
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @start_string
					AND DonatedOn <= @end_string) as 'DonatedLastYear'
			,(SELECT 
				FORMAT(COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0),'C', 'en-US') AS TotalAmount
	
				FROM 
					dbo.tw_Donation WITH(NOLOCK)
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @start_string
					AND DonatedOn <= @end_string ) as 'DonatedLastYearFormatted'
			, CAST(((((SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
	
				FROM 
					dbo.tw_Donation WITH(NOLOCK)
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @start_string
					AND DonatedOn <= @end_string) -
			(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @two_start
					AND DonatedOn <= @two_end))/(SELECT nullif(SUM(Amount),0) 
					FROM dbo.tw_Donation WITH(NOLOCK)
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @two_start
					AND DonatedOn <= @two_end)) * 100
			 )AS NVARCHAR(50)) as 'PercentChangeFromTwoFYAgoToOneFYAgo'
			 ,CONVERT(nvarchar(100),CONVERT(DATETIME, @two_start, 103),105) +'-'+ CONVERT(nvarchar(100),CONVERT(DATETIME, @two_end, 103),105) as 'FiscalTwoYearsAgo'
			,(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @two_start
					AND DonatedOn <= @two_end) as 'DonatedTwoYearsAgo'
			,(SELECT FORMAT(ROUND(ISNULL(SUM(Amount),0) , 2), 'C', 'en-US') 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @two_start
					AND DonatedOn <= @two_end) as 'DonatedTwoYearsAgoFormatted'
			,CAST(((((SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
	
				FROM 
					dbo.tw_Donation 
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @two_start
					AND DonatedOn <= @two_end) -
			(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @three_start
					AND DonatedOn <= @three_end))/(SELECT nullif(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @three_start
					AND DonatedOn <= @three_end)) * 100
			 )AS NVARCHAR(50)) as 'PercentChangeFromThreeFYAgoToTwoFYAgo'
			,CONVERT(nvarchar(100),CONVERT(DATETIME, @three_start, 103),105) +'-'+ CONVERT(nvarchar(100),CONVERT(DATETIME, @three_end, 103),105) as 'FiscalThreeYearsAgo'
			,(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @three_start
					AND DonatedOn <= @three_end) as 'DonatedThreeYearsAgo'
		
			,(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @three_start
					AND DonatedOn <= @three_end) as 'DonatedThreeYearsAgo'
			,(SELECT FORMAT(ROUND(ISNULL(SUM(Amount),0) , 2), 'C', 'en-US') 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @three_start
					AND DonatedOn <= @three_end) AS 'DonatedThreeYearsAgoFormatted' 
			,CAST(((((SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
	
				FROM 
					dbo.tw_Donation 
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @three_start
					AND DonatedOn <= @three_end) -
			(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @four_start
					AND DonatedOn <= @four_end))/(SELECT nullif(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @four_start
					AND DonatedOn <= @four_end)) * 100
			 )AS NVARCHAR(50)) as 'PercentChangeFromFourFYAgoToThreeFYAgo'
			,CONVERT(nvarchar(100),CONVERT(DATETIME, @four_start, 103),105) +'-'+ CONVERT(nvarchar(100),CONVERT(DATETIME, @four_end, 103),105) as 'FiscalFourYearsAgo'
			,(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @four_start
					AND DonatedOn <= @four_end) as 'DonatedFourYearsAgo'
			,(SELECT FORMAT(ROUND(ISNULL(SUM(Amount),0) , 2), 'C', 'en-US') 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @four_start
					AND DonatedOn <= @four_end) as 'DonatedFourYearsAgoFormatted'
			,CAST(((((SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
	
				FROM 
					dbo.tw_Donation 
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @four_start
					AND DonatedOn <= @four_end) -
			(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @five_start
					AND DonatedOn <= @five_end))/(SELECT nullif(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @five_start
					AND DonatedOn <= @five_end)) * 100
			 )AS NVARCHAR(50)) as 'PercentChangeFromFiveFYAgoToFourFYAgo'
			,CONVERT(nvarchar(100),CONVERT(DATETIME, @five_start, 103),105) +'-'+ CONVERT(nvarchar(100),CONVERT(DATETIME, @five_end, 103),105)as 'FiscalFiveYearsAgo'
			,(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @five_start
					AND DonatedOn <= @five_end) as 'DonatedFiveYearsAgo'
			,(SELECT FORMAT(ROUND(ISNULL(SUM(Amount),0) , 2), 'C', 'en-US')
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @five_start
					AND DonatedOn <= @five_end) as 'DonatedFiveYearsAgoFormatted'
			,CAST(((((SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
	
				FROM 
					dbo.tw_Donation 
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @five_start
					AND DonatedOn <= @five_end) -
			(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @six_start
					AND DonatedOn <= @six_end))/(SELECT nullif(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @six_start
					AND DonatedOn <= @six_end)) * 100
			 )AS NVARCHAR(50)) as 'PercentChangeFromSixFYAgoToFiveFYAgo'
			,CONVERT(nvarchar(100),CONVERT(DATETIME, @six_start, 103),105) +'-'+ CONVERT(nvarchar(100),CONVERT(DATETIME, @six_end, 103),105) as 'FiscalSixYearsAgo'
			,(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @six_start
					AND DonatedOn <= @six_end) as 'DonatedSixYearsAgo'
			,(SELECT FORMAT(ROUND(ISNULL(SUM(Amount),0) , 2), 'C', 'en-US')
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @six_start
					AND DonatedOn <= @six_end) as 'DonatedSixYearsAgoFormatted'
			, CAST(((((SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
	
				FROM 
					dbo.tw_Donation 
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @six_start
					AND DonatedOn <= @six_end)
					-
			(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @seven_start
					AND DonatedOn <= @seven_end))/(SELECT nullif(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @seven_start
					AND DonatedOn <= @seven_end)) * 100
			 )AS NVARCHAR(50)) as 'PercentChangeFromSevenFYAgoToSixFYAgo'
			,CONVERT(nvarchar(100),CONVERT(DATETIME, @seven_start, 103),105) +'-'+ CONVERT(nvarchar(100),CONVERT(DATETIME, @seven_end, 103),105) as 'FiscalSevenYearsAgo'
			,(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @seven_start
					AND DonatedOn <= @seven_end) as 'DonatedSevenYearsAgo'
			,(SELECT FORMAT(ROUND(ISNULL(SUM(Amount),0) , 2), 'C', 'en-US')
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @seven_start
					AND DonatedOn <= @seven_end) as 'DonatedSevenYearsAgoFormatted'
			,CAST(((((SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
	
				FROM 
					dbo.tw_Donation 
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @seven_start
					AND DonatedOn <= @seven_end) -
			(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @eight_start
					AND DonatedOn <= @eight_end))/(SELECT nullif(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @eight_start
					AND DonatedOn <= @eight_end)) * 100
			 )AS NVARCHAR(50)) as 'PercentChangeFromEightFYAgoToSevenFYAgo'
			 ,CONVERT(nvarchar(100),CONVERT(DATETIME, @eight_start, 103),105) +'-'+ CONVERT(nvarchar(100),CONVERT(DATETIME, @eight_end, 103),105) as 'FiscalEightYearsAgo'
			,(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @eight_start
					AND DonatedOn <= @eight_end) as 'DonatedEightYearsAgo'
			,(SELECT FORMAT(ROUND(ISNULL(SUM(Amount),0) , 2), 'C', 'en-US')
				FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @eight_start
					AND DonatedOn <= @eight_end) as 'DonatedEightYearsAgoFormatted'
			,CAST(((((SELECT 
				COALESCE(SUM(
					CASE 
						WHEN InKind = 1 AND Amount = 0 AND InKindFairMarketValue IS NOT NULL AND InKindFairMarketValue > 0 THEN InKindFairMarketValue
						WHEN IsStock = 1 AND StockFairMarketValue IS NOT NULL THEN StockFairMarketValue
						ELSE Amount
					END
				), 0) AS TotalAmount
	
				FROM 
					dbo.tw_Donation 
				WHERE 
					DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @eight_start
					AND DonatedOn <= @eight_end) -
			(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @nine_start
					AND DonatedOn <= @nine_end))/(SELECT nullif(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @nine_start
					AND DonatedOn <= @nine_end)) * 100
			 )AS NVARCHAR(50)) as 'PercentChangeFromNineFYAgoToEightFYAgo'
			,CONVERT(nvarchar(100),CONVERT(DATETIME, @nine_start, 103),105) +'-'+ CONVERT(nvarchar(100),CONVERT(DATETIME, @nine_end, 103),105) as 'FiscalNineYearsAgo'
			,(SELECT ISNULL(SUM(Amount),0) 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @nine_start
					AND DonatedOn <= @nine_end) as 'DonatedNineYearsAgo'
			,(SELECT FORMAT(ROUND(ISNULL(SUM(Amount),0) , 2), 'C', 'en-US') 
					FROM dbo.tw_Donation 
					WHERE DonorProfileID = dp.DonorProfileID 
					AND DonatedOn >= @nine_start
					AND DonatedOn <= @nine_end) as 'DonatedNineYearsAgoFormatted'
			,'' as 'FormattedDateString'
			,@campaign_title as 'DonationCampaignTitle'
			,FORMAT(@campaign_goal, '$#,##0') as 'DonationCampaignGoalFromTemplate'
			,FORMAT(@campaign_amountraised, '$#,##0') as 'DonationCampaignRaisedFromTemplate'
			,FORMAT(@campaign_goal - @campaign_amountraised, '$#,##0') as 'DonationCampaignRemainingFromTemplate'
			,CONCAT(ISNULL(@donation_percent,0),'%') as 'DonationCampaignPercentToGoalFromTemplate'
			,'' AS AverageDonationAllSchoolPreviousFY
			,'' as AverageDonationTopPercentilePreviousFY
			,'' as RecommendedAskStringWithThreeValues
			,'' AS RecommendedAskStringWithThreeValuesAndLinks
			,'' AS RecommendedAskStringWithFourValues
			,'' AS RecommendedAskStringWithFourValuesAndLinks
			,'' AS RecommendedAskStringWithFiveValues
			,'' As RecommendedAskStringWithFiveValuesAndLinks
			,'' AS 'RecommendedAskStringFromTemplateGivingLevels'
			,'' AS 'RecommendedAskStringFromTemplateGivingLevelsWithLinks'
			,'' AS 'RecommendedAskStringFromTemplateGivingLevelsWithTitles'
			,'' AS 'RecommendedAskStringFromTemplateGivingLevelsWithTitlesAndLinks'
			,(SELECT 
				CASE 
					WHEN @donation_url IS NOT NULL THEN CONCAT('<a href="', @donation_url, '" target="_blank">Donate Here</a>')
					ELSE NULL
				END) AS 'LinkToDonationForm'
			,@donation_url As 'UrlToDonationForm'
			,@all_school_average_donation_previous_FY_rounded as 'Average Donation All Donors Previous FY'
			,@all_school_top_pct_average_donation_previous_FY_rounded as 'Average Donation Top Donors Previous FY'
			,CONVERT(varchar, GETDATE(), 101) as 'CurrentDate'
			, (
			SELECT STRING_AGG(Title_amount, ', ') AS JoinedString
			FROM (
				SELECT dc.Title + ' ($' + CAST(SUM(d.Amount) AS VARCHAR(20)) + ')' AS Title_amount
				FROM tw_DonationCampaign dc
				INNER JOIN dbo.tw_Donation d ON dc.DonationCampaignID = d.DonationCampaignID
				WHERE d.DonorProfileID = dp.DonorProfileID 
				GROUP BY dc.Title) As subquery
				) As 'Campaigns'
			,(SELECT STRING_AGG(Title_amount, ', ') AS JoinedString
			FROM (
				SELECT dc.Title + ' ($' + CAST(SUM(d.Amount) AS VARCHAR(20)) + ')' AS Title_amount
				FROM tw_Fund dc
				INNER JOIN dbo.tw_Donation d ON dc.FundID = d.FundID
				WHERE d.DonorProfileID = dp.DonorProfileID 
				GROUP BY dc.Title
			) AS subquery) As 'Funds'
			,(SELECT STRING_AGG(Title_amount,', ') AS JoinedString
			  FROM (
					SELECT dc.Title + ' ($' + CAST(SUM(d.Amount) AS VARCHAR(20)) + ')' AS Title_amount
					FROM tw_DonationAppeal dc
						INNER JOIN dbo.tw_Donation d ON dc.DonationAppealID = d.DonationAppealID
						WHERE d.DonorProfileID = dp.DonorProfileID
						GROUP BY dc.Title
				   ) AS subquery) As 'Appeals'
			,(SELECT    NoteText+' ('+ u.UserName+', '+ CONVERT(VARCHAR(10), n.Created, 120) +')' AS UserTitle
				FROM  tw_Note AS n
				LEFT JOIN 
				tw_User AS u ON n.CreatedBy = u.UserID
				WHERE 
				n.ParentID = dp.DonorProfileID) As 'Notes'
			,'' AS 'SuggestedAskLowestCalculatedAmount'
			,'' AS 'SuggestedAskMiddleCalculatedAmount'
			,'' AS 'SuggestedAskHighestCalculatedAmount'
			,'' AS 'SuggestedAskFromAverageContribution'
			,'' AS 'SuggestedAskFromLatestContribution'
			,'' AS 'SuggestedAskFromLargestContribution'
			,'' AS 'SuggestedAskAmountForThoseWithoutDonationHistory'

			FROM 
				dbo.tw_DonorProfile  dp WITH (NOLOCK)
				LEFT JOIN dbo.tw_Address  a on a.AddressID = COALESCE(dp.OverrideAddressID, 
						 (SELECT TOP 1 AddressID FROM dbo.tw_AddressJoin WITH (NOLOCK) WHERE ParentID = (SELECT TOP 1 ParentID FROM dbo.tw_DonorProfileJoin WITH (NOLOCK) WHERE [Default] = 1 AND DonorProfileID = dp.DonorProfileID) AND [Default] = 1)) 
				LEFT JOIN dbo.tw_PhoneNumberJoin phj on phj.PhoneNumberID = COALESCE(dp.OverridePhoneNumberID, 
						 (SELECT TOP 1 PhoneNumberID FROM dbo.tw_PhoneNumberJoin WITH (NOLOCK) WHERE ParentID = (SELECT TOP 1 ParentID FROM dbo.tw_DonorProfileJoin WITH (NOLOCK) WHERE [Default] = 1 AND DonorProfileID = dp.DonorProfileID) AND [Default] = 1))
				LEFT JOIN dbo.tw_PhoneNumber  ph  WITH (NOLOCK)on ph.PhoneNumberID = phj.PhoneNumberID
				LEFT JOIN dbo.tw_EmailAddress  eid WITH (NOLOCK) on eid.EmailAddressID =COALESCE(dp.OverrideEmailAddressID, 
						 (SELECT TOP 1 EmailAddressID FROM dbo.tw_EmailAddress WITH (NOLOCK) WHERE ParentID = (SELECT TOP 1 ParentID FROM dbo.tw_DonorProfileJoin WITH (NOLOCK) WHERE [Default] = 1 AND DonorProfileID = dp.DonorProfileID)))
			--WHERE     dp.DonorProfileID in('1820a14f-dd74-4c2f-992b-55900ea18d8c')
			WHERE   NOT EXISTS (SELECT 1 FROM @ListDonorProfileIds) OR  dp.DonorProfileID IN (SELECT ProfileID FROM @ListDonorProfileIds)
		
	
			GROUP BY dp.DonorProfileID
			,dp.CalculatedGivingName
			,dp.CalculatedGreeting
			,dp.OverrideAddressID
			,a.SalutationFirstname
			,a.SalutationLastname
			,a.FamilySalutation
			,a.Address1
			,a.Address2
			,a.City
			,a.Region
			,a.PostalCode
			,eid.Email
			,ph.Number
			,dp.IsDonorAdvisedFund
			,a.CountryCode
		
		return;
	END
