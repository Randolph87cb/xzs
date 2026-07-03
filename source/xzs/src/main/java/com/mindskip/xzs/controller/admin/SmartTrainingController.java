package com.mindskip.xzs.controller.admin;

import com.mindskip.xzs.base.BaseApiController;
import com.mindskip.xzs.base.RestResponse;
import com.mindskip.xzs.base.SystemCode;
import com.mindskip.xzs.domain.SmartTrainingConfig;
import com.mindskip.xzs.repository.QuestionMapper;
import com.mindskip.xzs.service.SmartTrainingConfigService;
import com.mindskip.xzs.utility.JsonUtil;
import com.mindskip.xzs.viewmodel.admin.smarttraining.SmartTrainingConfigVM;
import com.mindskip.xzs.viewmodel.admin.smarttraining.SmartTrainingRuleVM;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.validation.Valid;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

@RestController("AdminSmartTrainingController")
@RequestMapping(value = "/api/admin/smartTraining")
public class SmartTrainingController extends BaseApiController {

    private final SmartTrainingConfigService smartTrainingConfigService;
    private final QuestionMapper questionMapper;

    @Autowired
    public SmartTrainingController(SmartTrainingConfigService smartTrainingConfigService, QuestionMapper questionMapper) {
        this.smartTrainingConfigService = smartTrainingConfigService;
        this.questionMapper = questionMapper;
    }

    @RequestMapping(value = "/config/list", method = RequestMethod.POST)
    public RestResponse<List<SmartTrainingConfig>> list() {
        return RestResponse.ok(smartTrainingConfigService.selectAll());
    }

    @RequestMapping(value = "/config/select/{subjectId}", method = RequestMethod.POST)
    public RestResponse<SmartTrainingConfigVM> select(@PathVariable Integer subjectId) {
        SmartTrainingConfig config = smartTrainingConfigService.selectBySubjectId(subjectId);
        SmartTrainingConfigVM vm = new SmartTrainingConfigVM();
        vm.setSubjectId(subjectId);
        if (config == null) {
            vm.setQuestionCount(20);
            vm.setRules(defaultRules());
            return RestResponse.ok(vm);
        }
        vm.setId(config.getId());
        vm.setQuestionCount(config.getQuestionCount());
        List<SmartTrainingRuleVM> rules = JsonUtil.toJsonListObject(config.getRuleJson(), SmartTrainingRuleVM.class);
        vm.setRules(rules == null || rules.isEmpty() ? defaultRules() : rules);
        return RestResponse.ok(vm);
    }

    @RequestMapping(value = "/config/edit", method = RequestMethod.POST)
    public RestResponse edit(@RequestBody @Valid SmartTrainingConfigVM model) {
        RestResponse validResult = validConfig(model);
        if (validResult.getCode() != SystemCode.OK.getCode()) {
            return validResult;
        }
        smartTrainingConfigService.saveConfig(model);
        return RestResponse.ok();
    }

    @RequestMapping(value = "/knowledgePoints/{subjectId}", method = RequestMethod.POST)
    public RestResponse<List<String>> knowledgePoints(@PathVariable Integer subjectId) {
        return RestResponse.ok(questionMapper.selectKnowledgePointsBySubjectId(subjectId));
    }

    private RestResponse validConfig(SmartTrainingConfigVM model) {
        int ruleQuestionCount = 0;
        Set<String> knowledgePoints = new HashSet<>();
        for (SmartTrainingRuleVM rule : model.getRules()) {
            String knowledgePoint = StringUtils.trim(rule.getKnowledgePoint());
            if (StringUtils.isBlank(knowledgePoint)) {
                return RestResponse.fail(2, "知识点不能为空");
            }
            if (!knowledgePoints.add(knowledgePoint)) {
                return RestResponse.fail(2, "知识点不能重复：" + knowledgePoint);
            }
            rule.setKnowledgePoint(knowledgePoint);
            ruleQuestionCount += rule.getQuestionCount();
        }
        if (ruleQuestionCount != model.getQuestionCount()) {
            return RestResponse.fail(2, "知识点题目数量之和必须等于总题数");
        }
        return RestResponse.ok();
    }

    private List<SmartTrainingRuleVM> defaultRules() {
        SmartTrainingRuleVM rule = new SmartTrainingRuleVM();
        rule.setKnowledgePoint("综合");
        rule.setQuestionCount(20);
        List<SmartTrainingRuleVM> rules = new ArrayList<>();
        rules.add(rule);
        return rules;
    }
}
