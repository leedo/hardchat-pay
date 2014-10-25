$(document).ready(function() {
  $('time[data-epoch]').each(function() {
    var date = moment.unix($(this).attr('data-epoch'));
    $(this).html(date.format("MMM Do YYYY"));
  });
});
