## Project Overview
New York City leadership relies on motor vehicle collision data to guide traffic safety policy, infrastructure planning, and enforcement strategies. With thousands of crashes occurring each year, understanding **where** severe collisions happen, **who** is most affected, and how **risk varies across boroughs** is critical for prioritizing interventions and allocating resources effectively. This analysis uses NYC crash data to provide a borough-level perspective on injuries and fatalities, supporting data-driven decisions aimed at improving street safety and reducing preventable loss of life.

Key areas that fueled insights and targeted recommendations include:
 - **Crash Trends Over Time:** Analyze long-term crash volume trends to distinguish sustained changes from short-term fluctuations.

 - **Borough-Level Risk and Severity:** Use risk-adjusted severity metrics to compare borough safety beyond raw crash counts.

 - **Vulnerable Road Users:** Assess injury and fatality risk for pedestrians, cyclists, and motorists to highlight disproportionate impacts.

 - **Contributing Factors:** Examine leading crash causes and how they vary across boroughs to inform targeted interventions.

 - **High-Risk Locations:** Identify streets and intersections with concentrated crash severity rather than just high volume.



An interactive dashboard in Power BI can be downloaded [here.](https://drive.google.com/file/d/1y8I7H01LmZmtQRFTuctt0C7xpPFn6NsH/view?usp=sharing)

The SQL queries used to clean, structure, and stage the data for analyzing can be viewed [here.](nyc_crash_data_cleaning.sql)

The SQL queries used to analyze overall data trends and specific insights can be viewed [here.](nyc_crash_data_analysis.sql)

An Excel workbook containing an issue log while data cleaning can be viewed [here.](nyc_crashes_issue_log.xlsx)

---

### Data Structure

---

### Data Quality Improvement
A substantial number of crash records lacked a reported borough despite containing valid latitude and longitude coordinates. To resolve this, borough values were derived using a geospatial point-in-polygon method, matching crash locations to official NYC borough boundary polygons. This approach allowed boroughs to be assigned deterministically based on geographic location rather than relying on incomplete or inconsistent source fields.

The process was implemented in Python to efficiently handle large-scale spatial joins. Only records with missing boroughs and valid coordinates were evaluated, preserving original data while improving completeness. Derived values were flagged for transparency, and crashes without sufficient geographic information were intentionally left unassigned. This enrichment significantly improved borough-level data quality and enabled more accurate severity and risk comparisons across boroughs.

The Python code used to accomplish this task can be viewed [here.](nyc-crashes-borough-fix.ipynb)

---

## Executive Summary
Overall crash volume in New York City peaked in 2018–2019 before declining by nearly 60% between 2020 and 2024. However, this reduction in crash frequency has not translated into proportional improvements in safety outcomes. While total crashes fell sharply following COVID-related travel shifts, crashes resulting in injury or death rebounded more quickly, and fatal risk per crash increased across boroughs and road user groups. These patterns indicate that fewer crashes have not necessarily resulted in safer conditions, highlighting the importance of monitoring severity—not just volume—when evaluating traffic safety progress.

*![dashboard overview page](nyc-overview-page)*

### Severity–Volume Divergence
 - Total crash volume peaked in 2018–2019, then declined sharply (≈60%) after 2020.
 - Harmful crashes (injury or death) rebounded faster than total crashes post‑2020.
 - Fatal crash risk per 10,000 crashes increased across boroughs and road user groups.
 - Fewer crashes did not translate into proportionally safer outcomes, underscoring the need to track severity—not just volume.

*![total crashes compared to harmful crashes](total-vs-harmful-crashes.png)*


2. Borough-Level Severity Disparities
• 	Fatal crash risk varies significantly across boroughs when normalized per 10,000 crashes.
• 	Staten Island consistently shows the highest fatal risk across pedestrians, cyclists, and motorists.
• 	Brooklyn and Manhattan show lower fatal risk per crash despite high crash volume.
• 	Borough rankings remain stable over time, suggesting structural differences rather than temporary fluctuations.

3. Vulnerable Road Users
• 	Pedestrians face roughly 3× higher fatal risk per crash compared to motorists and cyclists.
• 	Fatal crash risk increased after 2020 for all road user groups.
• 	Severity disparities widen for vulnerable users, especially cyclists.
• 	Manhattan remains among the lowest‑risk boroughs, while Staten Island remains the highest across all groups.

4. Temporal Risk Concentration
• 	Harmful crashes cluster heavily during weekday afternoons and early evenings (2–7 PM).
• 	Evening commute hours show higher harmful crash counts than morning commutes.
• 	Tuesday–Friday evenings exhibit the strongest concentration.
• 	These patterns indicate predictable temporal risk windows rather than random variation.

5. Behavioral Drivers of Harm
• 	Driver inattention and distraction are the leading contributors to injury‑ and fatal‑involved crashes.
• 	Failure to yield and following too closely are the next most common factors.
• 	Behavioral and interaction‑based errors account for the majority of harmful crashes.
• 	Unsafe speed appears less frequently but remains strongly associated with severe outcomes.

6. Geographic Concentration
• 	Harmful crashes are unevenly distributed across the street network.
• 	Major expressways account for a disproportionate share of severe crashes.
• 	A small number of recurring intersections consistently show elevated harmful crash counts.
• 	Crash harm clusters in persistent corridors and hotspots rather than isolated, one‑off locations.


### Recommendations

Severity-Based Performance Metrics
 - Shift performance tracking from crash counts to severity-based metrics. While total crashes have declined, crashes resulting in injury or death have increased, indicating that volume-based measures alone are insufficient. City agencies should prioritize metrics such as harmful crashes per 1,000 crashes and fatalities per 10,000 crashes to more accurately evaluate safety outcomes and identify emerging risk.

Vulnerable Road User Protections
 - Prioritize protections for vulnerable road users, particularly pedestrians. Pedestrians face substantially higher fatal risk per crash compared to other road users. Expanding traffic-calming measures, protected crossings, daylighted intersections, and speed-reduction interventions in pedestrian-heavy areas would directly address the highest-severity outcomes.

Time-Based Enforcement and Design
 - Target enforcement and street design changes during predictable high-risk periods. Harmful crashes consistently peak during late afternoon and early evening hours (2–7 PM), particularly from Tuesday through Saturday. Aligning enforcement, signal timing, and temporary traffic management measures with these high-risk windows would maximize the impact of limited safety resources.

Corridor- and Borough-Specific Interventions
 - Focus safety interventions on high-risk corridors and borough-specific needs. Major expressways account for a disproportionate share of harmful crashes, while borough-level fatal risk varies significantly across the city. Targeted corridor redesigns, speed management strategies, and borough-specific safety plans—particularly in Staten Island—are necessary to address uneven risk distribution and reduce severe crash outcomes.

### Additional Notes

