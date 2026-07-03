package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.SmartTrainingConfig;
import com.mindskip.xzs.repository.SmartTrainingConfigMapper;
import com.mindskip.xzs.service.SmartTrainingConfigService;
import com.mindskip.xzs.utility.JsonUtil;
import com.mindskip.xzs.viewmodel.admin.smarttraining.SmartTrainingConfigVM;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Date;
import java.util.List;

@Service
public class SmartTrainingConfigServiceImpl extends BaseServiceImpl<SmartTrainingConfig> implements SmartTrainingConfigService {

    private final SmartTrainingConfigMapper smartTrainingConfigMapper;

    @Autowired
    public SmartTrainingConfigServiceImpl(SmartTrainingConfigMapper smartTrainingConfigMapper) {
        super(smartTrainingConfigMapper);
        this.smartTrainingConfigMapper = smartTrainingConfigMapper;
    }

    @Override
    public SmartTrainingConfig selectBySubjectId(Integer subjectId) {
        return smartTrainingConfigMapper.selectBySubjectId(subjectId);
    }

    @Override
    public List<SmartTrainingConfig> selectAll() {
        return smartTrainingConfigMapper.selectAll();
    }

    @Override
    @Transactional
    public SmartTrainingConfig saveConfig(SmartTrainingConfigVM model) {
        Date now = new Date();
        SmartTrainingConfig config = smartTrainingConfigMapper.selectBySubjectId(model.getSubjectId());
        if (config == null) {
            config = new SmartTrainingConfig();
            config.setSubjectId(model.getSubjectId());
            config.setCreateTime(now);
            config.setDeleted(false);
        }
        config.setQuestionCount(model.getQuestionCount());
        config.setRuleJson(JsonUtil.toJsonStr(model.getRules()));
        config.setModifyTime(now);
        if (config.getId() == null) {
            smartTrainingConfigMapper.insertSelective(config);
        } else {
            smartTrainingConfigMapper.updateByPrimaryKeySelective(config);
        }
        return config;
    }
}
