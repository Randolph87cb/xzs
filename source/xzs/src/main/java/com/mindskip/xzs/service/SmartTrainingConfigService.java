package com.mindskip.xzs.service;

import com.mindskip.xzs.domain.SmartTrainingConfig;
import com.mindskip.xzs.viewmodel.admin.smarttraining.SmartTrainingConfigVM;

import java.util.List;

public interface SmartTrainingConfigService extends BaseService<SmartTrainingConfig> {

    SmartTrainingConfig selectBySubjectId(Integer subjectId);

    List<SmartTrainingConfig> selectAll();

    SmartTrainingConfig saveConfig(SmartTrainingConfigVM model);
}
