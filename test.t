def register(mcp: FastMCP) -> None:
    """Attach all Insight tools to *mcp*."""

    # ====================================================================== #
    # TOOL 1 — Portfolio Company Summary                                       #
    # ====================================================================== #
    @mcp.tool(
        name="get_portfolio_company_summary",
        description=(
            "Get the PROFILE / OVERVIEW of a portfolio company (PC). "
            "Use this FIRST when the user names a company — it returns the "
            "PortfolioCompanyId that KPI, deal, and holdings tools need."
        ),
        tags={"insight", "portfolio"},
        meta={"version": "1.0", "owner": "platform-team"},
    )
    async def get_portfolio_company_summary(
        PortfolioCompanyId: str = "",
        CompanyName: str = "",
        CompanyStatus: str = "",
        SectorName: str = "",
        SubSectorName: str = "",
        GroupName: str = "",
        ReportingCurrencyCode: str = "",
        pageNumber: int = 1,
        pageSize: int = 50,
    ) -> dict[str, Any]:
        """
        Get the PROFILE / OVERVIEW of a portfolio company (PC) — a real company that
        a fund has invested in. Use this FIRST when the user names a company, because
        it returns the **PortfolioCompanyId** that the KPI, deal, and holdings tools need.

        WHEN TO USE:
          - "Tell me about company X", "What sector is X in", "Who are X's co-investors".
          - As STEP 1 of a chain whenever you need a PortfolioCompanyId from a company name.

        INPUTS (all optional; pass only what you know — leave the rest blank):
          - CompanyName: full or partial company name to search.
          - PortfolioCompanyId: exact id if already known.
          - SectorName / CompanyStatus / GroupName / ReportingCurrencyCode: extra filters.

        OUTPUT: { data: [ { PortfolioCompanyId, CompanyName, SectorName, CompanyStatus,
                  PercentageOwnership, OtherCoinvestors, ReportingCurrencyCode, ... } ],
                  totalCount }. Extract `PortfolioCompanyId` to chain into
                  get_company_kpi_values / get_deal_overview / get_fund_holdings.
        """
        payload = {
            "filters": _clean({
                "PortfolioCompanyId": PortfolioCompanyId,
                "CompanyName": CompanyName,
                "CompanyStatus": CompanyStatus,
                "SectorName": SectorName,
                "SubSectorName": SubSectorName,
                "GroupName": GroupName,
                "ReportingCurrencyCode": ReportingCurrencyCode,
            }),
            "pageNumber": pageNumber,
            "pageSize": pageSize,
        }
        return await _post("/services/api/Insight/portfolio-company-summary", payload)

    # ====================================================================== #
    # TOOL 2 — Deal Overview                                                   #
    # ====================================================================== #
    @mcp.tool(
        name="get_deal_overview",
        description=(
            "Get DEALS — the relationship between a FUND and a PORTFOLIO COMPANY. "
            "Returns FundId and DealId. Use as a bridge from company → fund tools."
        ),
        tags={"insight", "deals"},
        meta={"version": "1.0", "owner": "platform-team"},
    )
    async def get_deal_overview(
        DealName: str = "",
        CompanyName: str = "",
        FundName: str = "",
        SectorName: str = "",
        InvestmentStage: str = "",
        ExitMethod: str = "",
        CurrencyCode: str = "",
        pageNumber: int = 1,
        pageSize: int = 50,
    ) -> dict[str, Any]:
        """
        Get DEALS — the relationship between a FUND and a PORTFOLIO COMPANY. A deal
        links a fund (the investor vehicle) to a company it invested in.

        WHEN TO USE:
          - "Which fund invested in company X?", "Show the deal/terms for X",
            "What stage / exit method / ownership for company X's investment".
          - As the BRIDGE step: returns **FundId** (chain into get_fund_track_record,
            get_fund_investors, get_fund_summary) and **DealId**.

        INPUTS (all optional): CompanyName, FundName, DealName, SectorName,
        InvestmentStage, ExitMethod, CurrencyCode.

        OUTPUT: { data: [ { DealId, PortfolioCompanyId, CompanyName, FundId, FundName,
                  InvestmentDate, CurrentExitOwnershipPercent, EnterpriseValue,
                  ExitMethod, InvestmentStage, SecurityType, ... } ], totalCount }.
        """
        payload = {
            "filters": _clean({
                "DealName": DealName,
                "CompanyName": CompanyName,
                "FundName": FundName,
                "SectorName": SectorName,
                "InvestmentStage": InvestmentStage,
                "ExitMethod": ExitMethod,
                "CurrencyCode": CurrencyCode,
            }),
            "pageNumber": pageNumber,
            "pageSize": pageSize,
        }
        return await _post("/services/api/Insight/deal-overview", payload)

    # ====================================================================== #
    # TOOL 3 — Fund Summary                                                    #
    # ====================================================================== #
    @mcp.tool(
        name="get_fund_summary",
        description=(
            "Get the PROFILE of a FUND: strategy, firm, currency, region, "
            "fund size, fees, vintage year, etc."
        ),
        tags={"insight", "fund"},
        meta={"version": "1.0", "owner": "platform-team"},
    )
    async def get_fund_summary(
        FundName: str = "",
        FirmName: str = "",
        Strategy: str = "",
        SectorName: str = "",
        CurrencyCode: str = "",
        VintageYear: str = "",
        RegionName: str = "",
        CountryName: str = "",
        pageNumber: int = 1,
        pageSize: int = 50,
    ) -> dict[str, Any]:
        """
        Get the PROFILE of a FUND (a fund is itself a company / investing vehicle):
        strategy, firm, currency, region, fund size, fees, vintage, etc.

        WHEN TO USE:
          - "Tell me about fund Y", "What strategy/region/currency is fund Y",
            "What firm manages fund Y".
          - If you only have a FundId from get_deal_overview, pass FundName
            (also returned by that tool) to look up the fund here.

        INPUTS (all optional): FundName, FirmName, Strategy, SectorName, CurrencyCode,
        VintageYear, RegionName, CountryName.

        OUTPUT: { data: [ { FundId, FundName, FirmName, Strategy, CurrencyCode,
                  RegionName, CountryName, ... } ], totalCount }.
        """
        payload = {
            "filters": _clean({
                "FundName": FundName,
                "FirmName": FirmName,
                "Strategy": Strategy,
                "SectorName": SectorName,
                "CurrencyCode": CurrencyCode,
            }),
            "VintageYear": VintageYear,
            "RegionName": RegionName,
            "CountryName": CountryName,
            "pageNumber": pageNumber,
            "pageSize": pageSize,
        }
        return await _post("/services/api/Insight/fund-summary", payload)
