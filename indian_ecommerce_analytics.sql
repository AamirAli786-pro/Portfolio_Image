use indian_ecommerce_analytics;

-- Verify table records count
SELECT 'customers' AS table_name, COUNT(*) AS total_rows FROM customers
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'sales', COUNT(*) FROM sales; 

Select * from customers;
select * from products;
Select * from sales limit 50;

Select 
	Customer_Age_Group,
	count(distinct Customer_ID) as Total_Customer,
    count(distinct Order_ID) as Total_Delivered_Orders,
	round(sum(sales.Total_Amount),2) as Total_Revenue,
	round(AVG(sales.Total_Amount),2) as AVG_Order_Value
from sales
where Sales.Order_Status = 'Delivered'
Group by Customer_Age_Group
order by Total_Revenue DESC
;

SELECT 
	p.Category,
    p.Brand, 
    count(distinct s.order_ID) as Total_Delivered_Orders,
    sum(s.Quantity) as Total_Units_Sold,
    Round(sum(s.Total_Amount),2) as Total_Revenue,
    Round(AVG(s.Total_Amount),2) as AVG_Order_Value
    from sales as s
	Inner Join Products as p 
    on s.Product_ID = p.Product_ID
    Where s.Order_Status = 'Delivered'
    and s.customer_Age_Group = '26-35'
    Group by p.Category,p.Brand
    Order by Total_Revenue DESC
    Limit 10;


;

select c.state,
	-- Metrics 1 : Order Volume
    count(distinct s.order_ID) as Total_Delivered_Orders,
    
    -- Metrics 2: Quantity Volume
    sum(s.Quantity) as Total_Units_Sold,
    
    -- Metrics 3: Financial Revenue
    
    round(sum(s.total_Amount),2) as Net_Realized_Revenue,
    
    -- Metrics 4 : Analyst Nuance (Average Order Value - AOV)
    
    round(sum(s.total_Amount)/Count(distinct s.order_ID),2) as AOV
    
    from sales s
    Inner join customers c on s.customer_ID = c.customer_id
    where s.order_status = 'Delivered'
    Group by c.state
    having Net_Realized_Revenue > 5000 -- Low performing Noise remove
    Order by Net_Realized_Revenue desc
    limit 10;
    
  
/*Question 1: Customer Repeat Purchase Gap (LAG Window Function)*/    
Select 
	Customer_ID, 
    Order_Date,
    LAG(Order_Date) over (Partition by Customer_ID order by Order_Date) As previous_Odate,
    datediff(Order_Date,LAG(Order_Date) over (Partition by Customer_ID order by Order_Date)) as Day_Diff_from_Pre_Order
	
from sales
;
/*Question 2: Month-over-Month (MoM) Revenue Growth & Running Total (SUM() OVER)*/
Select 
	Year_Name,
	month_name,
	Total_Quantity,
    Total_Revenue as 'Total_Revenue(IN_CR)',
    Sum(Total_Revenue) over (partition by Year_Name order by MN ) as C_R,
    concat(round((Total_Revenue-Lag (Total_Revenue) over (partition by Year_Name order by MN ))/Lag (Total_Revenue) over (partition by Year_Name order by MN )*100,2),'%') as 'Revenue_Growth%'
from (   
Select 
	date_format(Order_date, '%Y') as Year_Name, 
    month(Order_Date) as MN,
    monthname(Order_Date) as month_name,
    Sum(Quantity) as Total_Quantity,
    round(Sum(Total_Amount)/10000000,2) as Total_Revenue
from sales
group by 
	date_format(Order_date, '%Y'), 
    month(Order_Date), monthname(Order_Date)
order by 
date_format(Order_date, '%Y'),
month(Order_Date)) as MT;

/*Question 3: Category-wise Top 2 Best Selling Brands (DENSE_RANK + CTE)*/
With Best_Brand as (
Select 
Category,
Brand,
Sum(Total_Amount) as Total_Revenue
from sales as s
Inner Join products as p on p.Product_ID = s.Product_ID
Group by Category,
Brand
), Best_Brand_Rank as
(Select 
Category,
Brand,
Total_Revenue,
Dense_rank() 
over (partition by Category 
order by Total_Revenue DESC) as Brand_Rank
from Best_Brand) 
Select 
Category,
Brand,
Total_Revenue,
Brand_Rank
From Best_Brand_Rank
Where Brand_Rank IN (1,2);

/*Question 4: Identifying High-Risk "Serial Returner" Customers (Subquery / CTE)*/
select s.Customer_ID,
Count(s.Customer_ID) as Total_Sales_Orders,
Concat(
Cast(
sum(case when Order_Status = 'Returned' or Order_Status = 'Cancelled'
then 1 else 0  end)/Count(s.Customer_ID) as decimal(10,2))*100,'%') as returned
from sales as s
Inner Join customers as c on c.Customer_ID = s.Customer_ID
Group by s.Customer_ID
having Total_Sales_Orders >= 5  and returned > 40
;

/*Question 5: Payment Gateway Failure vs Order Value Threshold (Case Statements + Joins)*/
Select 
	Payment_mode,
    Count(*) as Total_Order,
    sum(Case
		When Total_Amount > 50000
        then 1
        else 0
        end) as High_Tickets,
	sum(Case
		When Total_Amount <= 50000
        then 1
        else 0
        end) as Low_Tickets,
	Concat(Cast(sum(Case
		When Total_Amount > 50000 and Order_status = 'Cancelled'
        then 1
        else 0
        end)/	sum(Case
		When Total_Amount <= 50000
        then 1
        else 0
        end)*100 as decimal(10,2)),'%') as High_Tickets_Cancellation,
	concat(cast(sum(Case
		When Total_Amount <= 50000 and Order_status = 'Cancelled'
        then 1
        else 0
        end)/	sum(Case
		When Total_Amount <= 50000
        then 1
        else 0
        end)*100 as decimal(10,2)),'%') as Low_Tickets_Cancellation        
from sales 
Group by Payment_mode;

/*Question 6: Seller / Brand Performance Scoreboard (PERCENT_RANK / Quantiles)*/
With Brand_Performance as 
(
Select
	Brand,
    sum(Total_Amount) as Revenue,
    Sum(
		(case
			When Order_Status = 'Cancelled'
            then 1
            else 0
            End
		*100))/count(*) as Cancellation_Rate
From
	sales

Inner Join Products on Products.Product_ID = sales.Product_ID
group by Brand
),
Brand_Percentile as 
(
	Select
		Brand,
        Revenue,
        Cancellation_Rate,
        percent_rank() over (order  by Revenue) as Revenue_Percentile,
        percent_rank() over (order  by Cancellation_Rate) as Cancellation_Percentile
 from 
	Brand_Performance
)
Select
	Brand,
    Revenue,
    Cancellation_Rate,
    Revenue_Percentile,
    Cancellation_Percentile
From Brand_Percentile
WHERE Revenue_Percentile >= 0.90
  AND Cancellation_Percentile >= 0.90;

/*Question 7: Customer RFM Segmentation - Recency, Frequency, Monetary (Complex CTEs)*/
WITH Customer_RFM AS
(select 
	Customer_ID,
    Max(Order_Date) as last_Order_Date,
    Count(*) as Frequency,
    Sum(Total_Amount) as Monetary
From
	sales
Group by Customer_ID),
RFM_Metrics AS
(
	Select 
    Customer_ID,
    DatedIff(curdate(),last_Order_Date) as Recency,
    Frequency,
    Monetary
From
	Customer_RFM),
RFM_Scores AS
(
	Select Customer_ID,
    Recency,
    Frequency,
    Monetary,
    ntile(4) over (order by Recency desc) as R_Score,
    ntile(4) over (order by Frequency) as F_Score,
    ntile(4) over (order by Monetary) as M_Score    
From
	RFM_Metrics)

Select
	Customer_ID,
    Recency,
    Frequency,
    Monetary,
    Case
		When R_Score = 4
        and F_Score = 4
        and	M_Score = 4
        then 'Champions'
        When R_Score <= 2
        and F_Score >= 3
        and M_Score >= 3
        then 'At Risk'
        When R_Score = 1
        and F_Score = 1
        and M_Score = 1
        then 'Lost'
        else 'Other'
        end as Customer_Segment
from
	RFM_Scores;
/*Question 8: First-Touch Category vs Lifetime Value Correlation (FIRST_VALUE)*/

With Customer_Data as
(
Select Distinct
	Customer_ID,
    First_Value(p.Category) over (Partition by Customer_ID order by Order_Date) as First_Category,
    sum(Total_Amount) over (Partition by Customer_ID) as LTV
From
	sales as s
Inner Join Products as p
	on p.Product_ID = s.Product_ID
)
Select 
	First_Category,
    AVG(LTV) as Average_LTV
From Customer_Data
Group by
	First_Category;
/*Question 9: Monthly Customer Cohort Retention Rate (Cohort Matrix)*/
With Customer_Cohort as 
(
Select 
	Customer_ID,
    date_format(min(Order_Date),'%Y-%m') as Cohort_Month
from sales
Group by
		Customer_ID),

Customer_Purchases AS
(Select
	Customer_ID,
    Date_format(Order_Date,'%Y-%m') as Purchase_Month
From
	sales
Order By
	Customer_ID)
select 
    C.Cohort_Month,
    P.Purchase_Month,
    COUNT(DISTINCT C.Customer_ID) AS Active_Customers,
    ROUND(
        COUNT(DISTINCT C.Customer_ID) * 100.0
        / MAX(COUNT(DISTINCT C.Customer_ID)) OVER (),
        2
    ) AS Retention_Percentage
from Customer_Cohort as c
Inner Join Customer_Purchases as p
	On C.Customer_ID = P.Customer_ID
Where
	c.Cohort_Month = '2025-01'	
Group by
	c.Cohort_Month,
    p.Purchase_Month
ORDER BY
    C.Cohort_Month,
    P.Purchase_Month;
/*Question 10: State-wise Delivery Velocity & Revenue Loss (LEAD or Time Differences)*/

SELECT 
  State,
  COUNT(Order_ID) AS Total_Orders,
  ROUND(AVG(DATEDIFF(STR_TO_DATE(Delivery_Date, '%Y-%m-%d'), STR_TO_DATE(Order_Date, '%Y-%m-%d'))), 1) AS Avg_Delivery_Days,
  
  -- Return Rate
  SUM(CASE WHEN Order_Status = 'Returned' THEN 1 ELSE 0 END) AS Total_Returns,
  ROUND(SUM(CASE WHEN Order_Status = 'Returned' THEN 1 ELSE 0 END) * 100.0 / COUNT(Order_ID), 2) AS Return_Rate_Percent,
  
  -- Revenue Loss
  SUM(CASE WHEN Order_Status = 'Returned' THEN Total_Amount ELSE 0 END) AS Revenue_Lost,
  SUM(Total_Amount) AS Total_Revenue,
  ROUND(SUM(CASE WHEN Order_Status = 'Returned' THEN Total_Amount ELSE 0 END) * 100.0 / SUM(Total_Amount), 2) AS Revenue_Loss_Percent

FROM sales
GROUP BY State
ORDER BY Avg_Delivery_Days DESC;        
        

