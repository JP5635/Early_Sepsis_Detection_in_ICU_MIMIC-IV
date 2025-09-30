SELECT hadm_id, stay_id, sofa_start, sofa_end, 
        MAX(sofa_resp) AS sofa_resp, 
        MAX(sofa_coag) AS sofa_coag, 
        MAX(sofa_liver) AS sofa_liver, 
        MAX(sofa_cardio) AS sofa_cardio, 
        MAX(sofa_cns) AS sofa_cns, 
        MAX(sofa_renal) AS sofa_renal, 
        IFNULL(MAX(sofa_resp), 0) + IFNULL(MAX(sofa_coag), 0) + 
        IFNULL(MAX(sofa_liver), 0) + IFNULL(MAX(sofa_cardio), 0) + 
        IFNULL(MAX(sofa_cns), 0) + IFNULL(MAX(sofa_renal), 0) AS sofa_total
FROM `ethereal-argon-164612.P1.SOFA_Score_ALL`
GROUP BY hadm_id, stay_id, sofa_start, sofa_end
ORDER BY hadm_id, stay_id, sofa_start
