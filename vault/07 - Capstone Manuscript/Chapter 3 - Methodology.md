---
title: "Chapter 3 - Methodology"
category: "Capstone Manuscript"
chapter: 3
created: 2026-09-26
last_updated: 2026-09-26
tags:
  - capstone
  - chapter-3
  - methodology
  - research-design
  - sus
---

# Chapter 3: Methodology

This chapter outlines the research methodology employed by the proponents to conceptualize, design, develop, and evaluate the **Operation Management Application for AA Slaughterhouse of Tabaco City**. It details the data gathering techniques, primary and secondary data sources, statistical analysis tools, participant sampling procedures, and mathematical psychometric formulation utilized throughout the study.

---

## Data Gathering Techniques

The proponents utilized a comprehensive, multi-method data collection approach combining qualitative and quantitative research techniques:

### 1. In-Depth Interviews
An interview is a qualitative research method where researchers ask direct questions to participants to obtain in-depth, nuanced operational information (George, 2023). The proponents conducted structured and semi-structured interviews with slaughterhouse managers, veterinary meat inspectors, receiving staff, and cashier personnel at the Tabaco City Slaughterhouse. The objective was to identify existing operational bottlenecks in manual record-keeping, map physical livestock inspection sequences, and gather functional requirements for the digital platform.

### 2. Structured Questionnaires
A questionnaire is a research instrument consisting of a standardized set of questions aimed at collecting consistent data from a broad group of respondents (Hassan, 2024). Questionnaires were administered to local hog raisers, cattle farmers, and commercial meat dealers across Tabaco City. The questions captured user preferences regarding digital booking, permit upload workflows, SMS/push notifications, and preferred payment channels (Cash vs. GCash).

### 3. Survey Method
A survey is a comprehensive research method used to systematically collect, analyze, and interpret data from a sample population (Fowler, 2020). The survey was deployed using Google Forms and distributed on-site via QR codes to evaluate digital literacy, smartphone accessibility, and readiness for mobile abattoir booking. Furthermore, the standardized System Usability Scale (SUS) survey was administered post-deployment to assess system usability and effectiveness.

### 4. Document Analysis
Document analysis involves reviewing existing physical records, inspection logs, and transaction reports to extract factual administrative data (Bowen, 2009). The researchers examined physical animal intake ledgers, official Meat Inspection Certificates (MIC), condemnation and confiscation logs, municipal fee assessment slips, and monthly production summaries to ensure the software’s data models strictly complied with National Meat Inspection Service (NMIS) and Tabaco City LGU reporting standards.

---

## Sources of Data

The study gathered data from primary and secondary sources:

### Primary Sources
1. **Slaughterhouse Staff & Receiving Clerks**: Provided detailed accounts of physical animal receiving, holding corral capacity management, ear-tagging, and daily slaughter queueing.
2. **Veterinary Meat Inspectors**: Shared clinical insights into ante-mortem evaluation, humane stunning protocols, post-mortem visceral examination, carcass weight recording, and statutory condemnation slip issuance.
3. **Slaughterhouse Administrative & Cashier Personnel**: Provided information on municipal fee schedules, revenue auditing, official receipt generation, and gate pass release validation.
4. **Commercial Meat Dealers & Backyard Livestock Raisers**: Provided customer-side data regarding service expectations, remote scheduling, and digital payment readiness.

### Secondary Sources
1. **Government & Regulatory Publications**: Republic Act No. 9296 (The Meat Inspection Code of the Philippines), R.A. 10536, NMIS Administrative Orders, and Department of Agriculture guidelines.
2. **International Reports**: Publications from the Food and Agriculture Organization (FAO), World Health Organization (WHO), and Humane Society International (HSI).
3. **Academic Literature**: Peer-reviewed journal articles and case studies on abattoir automation, cloud database architectures, and digital public sector governance.

---

## Tools for Data Analysis

The data collected was tabulated, analyzed, and visualized using the following tools:

1. **Microsoft Excel**: Utilized as a spreadsheet engine for data cleaning, frequency tabulation, mathematical formulation, and initial visual charting (Alshammari, 2023).
2. **Google Forms & Google Sheets**: Employed for cloud-based survey creation, automated response recording, and real-time data collation (Bhat, 2024; Neil, 2020).
3. **Google Looker Studio**: Used to construct interactive visual business intelligence dashboards tracking user survey responses and abattoir operational metrics.
4. **IBM SPSS Statistics (v28)**: Utilized as the primary statistical software suite to execute descriptive analyses (mean, standard deviation), compute composite System Usability Scale (SUS) metrics, and perform psychometric subscale factor reliability tests (Field, 2020; Pallant, 2023).

---

## Sampling Procedure

The study utilized **Purposive Sampling** (judgmental sampling), a non-probability sampling technique where researchers deliberately select participants based on specific operational characteristics, domain knowledge, and direct involvement in slaughterhouse operations (Campbell et al., 2020; Etikan et al., 2016).

A total sample of **$N = 46$ participants** was stratified across five operational stakeholder tiers:
1. **Slaughterhouse Management**: $n = 2$ (Supervisor, City Veterinarian)
2. **Veterinary Meat Inspectors**: $n = 4$ (NMIS Accredited Inspectors)
3. **Operations Staff & Cashiers**: $n = 4$ (Receiving clerks, Cashiers)
4. **Abattoir Butchers & Handlers**: $n = 6$ (Slaughter line workers)
5. **Commercial Meat Dealers & Farmers**: $n = 30$ (Public market stallholders, local livestock raisers)

---

## System Usability Scale (SUS) Mathematical Formulation

To evaluate the operational acceptability, learnability, and perceived efficiency of the developed system, the standardized 10-item System Usability Scale (SUS) framework was implemented (Lee et al., 2023; Lubua & Elias, 2021).

The instrument employs ten 5-point Likert-scale statements ($1 = \text{Strongly Disagree}$ to $5 = \text{Strongly Agree}$), alternating between positive and negative assertions to mitigate acquiescence bias.

### Mathematical Formulation
In accordance with standard SUS scoring protocol:

1. For odd-numbered positive items ($i \in \{1, 3, 5, 7, 9\}$), the score contribution is calculated by subtracting 1 from the raw response value ($Q_i$):
   $$ON = \sum_{i \in \{1, 3, 5, 7, 9\}} (Q_i - 1)$$

2. For even-numbered negative items ($i \in \{2, 4, 6, 8, 10\}$), the score contribution is calculated by subtracting the raw response value ($Q_i$) from 5:
   $$EN = \sum_{i \in \{2, 4, 6, 8, 10\}} (5 - Q_i)$$

3. The individual composite SUS score is derived by multiplying the sum of all adjusted item contributions by 2.5, yielding a standardized metric on a scale from 0 to 100:
   $$SUS = (ON + EN) \times 2.5$$

4. Following psychometric factor structure analysis (Lallemand & Gronier, 2023; Lewis & Sauro, 2009), the 10 SUS items decompose into two distinct subscales:
   - **Usability Subscale**: Encompassing Items Q1, Q2, Q3, Q5, Q6, Q7, Q8, and Q9.
   - **Learnability Subscale**: Encompassing Items Q4 and Q10.
