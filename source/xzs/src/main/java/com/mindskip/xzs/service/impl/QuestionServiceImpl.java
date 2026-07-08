package com.mindskip.xzs.service.impl;

import com.mindskip.xzs.domain.other.KeyValue;
import com.mindskip.xzs.domain.Question;
import com.mindskip.xzs.domain.TextContent;
import com.mindskip.xzs.domain.enums.QuestionStatusEnum;
import com.mindskip.xzs.domain.enums.QuestionTypeEnum;
import com.mindskip.xzs.domain.question.QuestionItemObject;
import com.mindskip.xzs.domain.question.QuestionObject;
import com.mindskip.xzs.repository.QuestionMapper;
import com.mindskip.xzs.service.QuestionService;
import com.mindskip.xzs.service.SubjectService;
import com.mindskip.xzs.service.TextContentService;
import com.mindskip.xzs.utility.DateTimeUtil;
import com.mindskip.xzs.utility.JsonUtil;
import com.mindskip.xzs.utility.ModelMapperSingle;
import com.mindskip.xzs.utility.ExamUtil;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditItemVM;
import com.mindskip.xzs.viewmodel.admin.question.QuestionEditRequestVM;
import com.mindskip.xzs.viewmodel.admin.question.QuestionPageRequestVM;
import com.github.pagehelper.PageHelper;
import com.github.pagehelper.PageInfo;
import org.apache.commons.lang3.StringUtils;
import org.modelmapper.ModelMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class QuestionServiceImpl extends BaseServiceImpl<Question> implements QuestionService {

    protected final static ModelMapper modelMapper = ModelMapperSingle.Instance();
    private final QuestionMapper questionMapper;
    private final TextContentService textContentService;
    private final SubjectService subjectService;
    private final JdbcTemplate jdbcTemplate;

    @Autowired
    public QuestionServiceImpl(QuestionMapper questionMapper, TextContentService textContentService, SubjectService subjectService, JdbcTemplate jdbcTemplate) {
        super(questionMapper);
        this.textContentService = textContentService;
        this.questionMapper = questionMapper;
        this.subjectService = subjectService;
        this.jdbcTemplate = jdbcTemplate;
    }

    @Override
    public PageInfo<Question> page(QuestionPageRequestVM requestVM) {
        return PageHelper.startPage(requestVM.getPageIndex(), requestVM.getPageSize(), "id desc").doSelectPageInfo(() ->
                questionMapper.page(requestVM)
        );
    }


    @Override
    @Transactional
    public Question insertFullQuestion(QuestionEditRequestVM model, Integer userId) {
        Date now = new Date();
        Integer gradeLevel = subjectService.levelBySubjectId(model.getSubjectId());

        //题干、解析、选项等 插入
        TextContent infoTextContent = new TextContent();
        infoTextContent.setCreateTime(now);
        setQuestionInfoFromVM(infoTextContent, model);
        textContentService.insertByFilter(infoTextContent);

        Question question = new Question();
        question.setSubjectId(model.getSubjectId());
        question.setGradeLevel(gradeLevel);
        question.setCreateTime(now);
        question.setQuestionType(model.getQuestionType());
        question.setStatus(QuestionStatusEnum.OK.getCode());
        question.setCorrectFromVM(model.getCorrect(), model.getCorrectArray());
        question.setScore(ExamUtil.scoreFromVM(model.getScore()));
        question.setDifficult(model.getDifficult());
        question.setKnowledgePoint(normalizeKnowledgePoint(model.getKnowledgePoint()));
        question.setInfoTextContentId(infoTextContent.getId());
        question.setCreateUser(userId);
        question.setDeleted(false);
        questionMapper.insertSelective(question);
        return question;
    }

    @Override
    @Transactional
    public Question updateFullQuestion(QuestionEditRequestVM model) {
        Integer gradeLevel = subjectService.levelBySubjectId(model.getSubjectId());
        Question question = questionMapper.selectByPrimaryKey(model.getId());
        question.setSubjectId(model.getSubjectId());
        question.setGradeLevel(gradeLevel);
        question.setScore(ExamUtil.scoreFromVM(model.getScore()));
        question.setDifficult(model.getDifficult());
        question.setKnowledgePoint(normalizeKnowledgePoint(model.getKnowledgePoint()));
        question.setCorrectFromVM(model.getCorrect(), model.getCorrectArray());
        questionMapper.updateByPrimaryKeySelective(question);

        //题干、解析、选项等 更新
        TextContent infoTextContent = textContentService.selectById(question.getInfoTextContentId());
        setQuestionInfoFromVM(infoTextContent, model);
        textContentService.updateByIdFilter(infoTextContent);

        return question;
    }

    @Override
    public QuestionEditRequestVM getQuestionEditRequestVM(Integer questionId) {
        //题目映射
        Question question = questionMapper.selectByPrimaryKey(questionId);
        return getQuestionEditRequestVM(question);
    }

    @Override
    public QuestionEditRequestVM getQuestionEditRequestVM(Question question) {
        //题目映射
        TextContent questionInfoTextContent = textContentService.selectById(question.getInfoTextContentId());
        QuestionObject questionObject = JsonUtil.toJsonObject(questionInfoTextContent.getContent(), QuestionObject.class);
        QuestionEditRequestVM questionEditRequestVM = modelMapper.map(question, QuestionEditRequestVM.class);
        questionEditRequestVM.setTitle(questionObject.getTitleContent());

        //答案
        QuestionTypeEnum questionTypeEnum = QuestionTypeEnum.fromCode(question.getQuestionType());
        switch (questionTypeEnum) {
            case SingleChoice:
            case TrueFalse:
                questionEditRequestVM.setCorrect(question.getCorrect());
                break;
            case MultipleChoice:
                questionEditRequestVM.setCorrectArray(ExamUtil.contentToArray(question.getCorrect()));
                break;
            case GapFilling:
                List<String> correctContent = questionObject.getQuestionItemObjects().stream().map(d -> d.getContent()).collect(Collectors.toList());
                questionEditRequestVM.setCorrectArray(correctContent);
                break;
            case ShortAnswer:
                questionEditRequestVM.setCorrect(questionObject.getCorrect());
                break;
            default:
                break;
        }
        questionEditRequestVM.setScore(ExamUtil.scoreToVM(question.getScore()));
        questionEditRequestVM.setAnalyze(questionObject.getAnalyze());


        //题目项映射
        List<QuestionEditItemVM> editItems = questionObject.getQuestionItemObjects().stream().map(o -> {
            QuestionEditItemVM questionEditItemVM = modelMapper.map(o, QuestionEditItemVM.class);
            if (o.getScore() != null) {
                questionEditItemVM.setScore(ExamUtil.scoreToVM(o.getScore()));
            }
            return questionEditItemVM;
        }).collect(Collectors.toList());
        questionEditRequestVM.setItems(editItems);
        return questionEditRequestVM;
    }

    @Override
    @Transactional
    public Map<String, Object> normalizeGespKnowledgePointsBySubject() {
        String importedQuestionCte = "WITH imported AS ( " +
                "select q.id, q.info_text_content_id, " +
                "(regexp_match(translate(tc.content::jsonb ->> 'importSource', chr(92), '/'), '^([0-9]{4})-([0-9]{2})/C\\+\\+-([0-9]+)/(选择题|判断题)\\.md$'))[3] as gesp_level, " +
                "regexp_replace(coalesce(nullif(q.knowledge_point, ''), '综合'), '^GESP[1-8]级/', '') as base_knowledge_point " +
                "from t_question q join t_text_content tc on tc.id = q.info_text_content_id " +
                "where q.deleted = false and tc.content::jsonb ->> 'importBatch' = 'GESP_OBJECTIVE_MD' " +
                "), normalized AS ( " +
                "select id, info_text_content_id, 'GESP' || gesp_level || '级/' || base_knowledge_point as scoped_knowledge_point " +
                "from imported where gesp_level is not null " +
                ") ";

        String updateQuestionSql = importedQuestionCte +
                "update t_question q set knowledge_point = n.scoped_knowledge_point " +
                "from normalized n " +
                "where q.id = n.id and q.knowledge_point is distinct from n.scoped_knowledge_point " +
                "returning q.id";
        List<Integer> updatedQuestionIds = jdbcTemplate.queryForList(updateQuestionSql, Integer.class);

        String updateTextContentSql = importedQuestionCte +
                "update t_text_content tc set content = jsonb_set(tc.content::jsonb, '{knowledgePoint}', to_jsonb(n.scoped_knowledge_point))::text " +
                "from normalized n " +
                "where tc.id = n.info_text_content_id " +
                "and tc.content::jsonb ->> 'knowledgePoint' is distinct from n.scoped_knowledge_point " +
                "returning tc.id";
        List<Integer> updatedContentIds = jdbcTemplate.queryForList(updateTextContentSql, Integer.class);

        String updateConfigSql = "update t_smart_training_config c set rule_json = normalized.rule_json " +
                "from ( " +
                "select c2.id, jsonb_agg(jsonb_set(rule.value, '{knowledgePoint}', to_jsonb('GESP' || c2.subject_id || '级/' || regexp_replace(coalesce(nullif(rule.value ->> 'knowledgePoint', ''), '综合'), '^GESP[1-8]级/', ''))) order by rule.ordinality)::text as rule_json " +
                "from t_smart_training_config c2 " +
                "cross join lateral jsonb_array_elements(c2.rule_json::jsonb) with ordinality as rule(value, ordinality) " +
                "where c2.subject_id between 1 and 8 and c2.rule_json is not null and c2.rule_json <> '' " +
                "group by c2.id " +
                ") normalized " +
                "where c.id = normalized.id and c.rule_json is distinct from normalized.rule_json";
        int updatedConfigCount = jdbcTemplate.update(updateConfigSql);

        List<Map<String, Object>> subjectSummary = jdbcTemplate.queryForList(
                "select subject_id, count(*) as question_count, count(distinct knowledge_point) as knowledge_point_count " +
                        "from t_question where deleted = false and subject_id between 1 and 8 and knowledge_point like 'GESP%级/%' " +
                        "group by subject_id order by subject_id");

        Map<String, Object> result = new HashMap<>();
        result.put("updatedQuestionCount", updatedQuestionIds.size());
        result.put("updatedContentCount", updatedContentIds.size());
        result.put("updatedSmartTrainingConfigCount", updatedConfigCount);
        result.put("subjectSummary", subjectSummary);
        return result;
    }

    public void setQuestionInfoFromVM(TextContent infoTextContent, QuestionEditRequestVM model) {
        List<QuestionItemObject> itemObjects = model.getItems().stream().map(i ->
                {
                    QuestionItemObject item = new QuestionItemObject();
                    item.setPrefix(i.getPrefix());
                    item.setContent(i.getContent());
                    item.setItemUuid(i.getItemUuid());
                    item.setScore(ExamUtil.scoreFromVM(i.getScore()));
                    return item;
                }
        ).collect(Collectors.toList());
        QuestionObject questionObject = new QuestionObject();
        questionObject.setQuestionItemObjects(itemObjects);
        questionObject.setAnalyze(model.getAnalyze());
        questionObject.setTitleContent(model.getTitle());
        questionObject.setCorrect(model.getCorrect());
        infoTextContent.setContent(JsonUtil.toJsonStr(questionObject));
    }

    private String normalizeKnowledgePoint(String knowledgePoint) {
        return StringUtils.isBlank(knowledgePoint) ? "综合" : knowledgePoint.trim();
    }

    @Override
    public Integer selectAllCount() {
        return questionMapper.selectAllCount();
    }

    @Override
    public List<Integer> selectMothCount() {
        Date startTime = DateTimeUtil.getMonthStartDay();
        Date endTime = DateTimeUtil.getMonthEndDay();
        List<String> mothStartToNowFormat = DateTimeUtil.MothStartToNowFormat();
        List<KeyValue> mouthCount = questionMapper.selectCountByDate(startTime, endTime);
        return mothStartToNowFormat.stream().map(md -> {
            KeyValue keyValue = mouthCount.stream().filter(kv -> kv.getName().equals(md)).findAny().orElse(null);
            return null == keyValue ? 0 : keyValue.getValue();
        }).collect(Collectors.toList());
    }


}
